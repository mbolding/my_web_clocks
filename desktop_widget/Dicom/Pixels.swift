// Pixels — what a file's image is (size, bit depth, photometric interpretation, frames,
// and each frame's rescale, window and position), decoding a frame to modality values
// or RGB, and drawing it through a window. Uncompressed and RLE pixels are decoded here;
// JPEG and JPEG 2000 frames go through ImageIO.

import Foundation
import CoreGraphics
import ImageIO
import Accelerate

struct ImageInfo {
    let rows: Int
    let columns: Int
    let bitsAllocated: Int
    let bitsStored: Int
    let samples: Int
    let signed: Bool
    let photometric: String
    let planar: Int
    let frameCount: Int
    let pixels: DicomElement
    let modalityLUT: LUT?
    let frames: [FrameInfo]

    var isColor: Bool { samples == 3 || photometric == "PALETTE COLOR" }

    struct FrameInfo {
        var position: [Double]?
        var orientation: [Double]?
        /// Row spacing, then column spacing, in mm.
        var spacing: [Double]?
        var slope = 1.0
        var intercept = 0.0
        var centers: [Double] = []
        var widths: [Double] = []
    }

    /// A Modality or VOI LUT: entries, the first value mapped, and one output per entry.
    struct LUT {
        let first: Int
        let data: [UInt16]
        let explanation: String

        init?(item: DataSet, file: DicomFile, signed: Bool) {
            guard let descriptor = file.numbers(0x0028_3002, in: item), descriptor.count >= 3,
                  let element = item[0x0028_3006] else { return nil }
            let count = descriptor[0] == 0 ? 65536 : Int(descriptor[0])
            var first = Int(descriptor[1])
            if signed && first > 32767 { first -= 65536 }
            if element.length >= 2 * count {
                data = (DicomFile.binaryNumbers(element, vr: "US", max: count) ?? []).map { UInt16($0) }
            } else if element.length >= count {
                data = element.bytes.prefix(count).map { UInt16($0) }
            } else {
                return nil
            }
            self.first = first
            explanation = file.string(0x0028_3003, in: item)
        }

        func callAsFunction(_ value: Int) -> Float {
            Float(data[min(max(value - first, 0), data.count - 1)])
        }
    }

    init?(file: DicomFile) {
        let d = file.dataSet
        guard let pixels = d[Tag.pixelData],
              let rows = file.number(0x0028_0010).map(Int.init), let columns = file.number(0x0028_0011).map(Int.init),
              rows > 0, columns > 0 else { return nil }
        self.rows = rows
        self.columns = columns
        self.pixels = pixels
        bitsAllocated = file.number(0x0028_0100).map(Int.init) ?? 16
        bitsStored = file.number(0x0028_0101).map(Int.init) ?? bitsAllocated
        samples = file.number(0x0028_0002).map(Int.init) ?? 1
        signed = file.number(0x0028_0103) == 1
        photometric = (file.string(0x0028_0004).isEmpty ? "MONOCHROME2" : file.string(0x0028_0004)).uppercased()
        planar = file.number(0x0028_0006).map(Int.init) ?? 0
        frameCount = max(1, Int(file.number(0x0028_0008)?.rounded() ?? 1))
        modalityLUT = d[0x0028_3000]?.items?.first.flatMap { LUT(item: $0, file: file, signed: file.number(0x0028_0103) == 1) }

        // Enhanced multi-frame files keep geometry and scaling in functional groups, per
        // frame or shared; the classic tags are the fallback.
        let shared = d[0x5200_9229]?.items?.first
        let perFrame = d[0x5200_9230]?.items
        var frames: [FrameInfo] = []
        for f in 0..<frameCount {
            func look(_ sequence: UInt32, _ tag: UInt32) -> [Double]? {
                for group in [perFrame.flatMap { f < $0.count ? $0[f] : nil }, shared] {
                    if let item = group?[sequence]?.items?.first, item[tag] != nil { return file.numbers(tag, in: item) }
                }
                return file.numbers(tag)
            }
            var frame = FrameInfo()
            frame.position = look(0x0020_9113, 0x0020_0032).flatMap { $0.count == 3 ? $0 : nil }
            frame.orientation = look(0x0020_9116, 0x0020_0037).flatMap { $0.count == 6 ? $0 : nil }
            frame.spacing = (look(0x0028_9110, 0x0028_0030) ?? file.numbers(0x0018_1164)).flatMap { $0.count >= 2 && $0[0] > 0 && $0[1] > 0 ? $0 : nil }
            if let slope = look(0x0028_9145, 0x0028_1053)?.first, slope.isFinite, slope != 0 { frame.slope = slope }
            if let intercept = look(0x0028_9145, 0x0028_1052)?.first, intercept.isFinite { frame.intercept = intercept }
            frame.centers = look(0x0028_9132, 0x0028_1050) ?? []
            frame.widths = look(0x0028_9132, 0x0028_1051) ?? []
            frames.append(frame)
            // Without per-frame groups every frame is the same, so don't look 500 times.
            if perFrame == nil && f == 0 && frameCount > 1 {
                frames += Array(repeating: frame, count: frameCount - 1)
                break
            }
        }
        self.frames = frames
    }
}

/// One frame ready to draw: modality values for greyscale, or 8-bit RGB.
struct DecodedFrame {
    enum Pixels {
        case gray([Float])
        case rgb([UInt8])
    }

    let width: Int
    let height: Int
    let pixels: Pixels
    let minimum: Float
    let maximum: Float
    /// The 1st and 99th percentiles, for the Auto window.
    let low: Float
    let high: Float

    init(width: Int, height: Int, pixels: Pixels) {
        self.width = width
        self.height = height
        self.pixels = pixels
        guard case .gray(let values) = pixels, !values.isEmpty else {
            (minimum, maximum, low, high) = (0, 255, 0, 255)
            return
        }
        var lo: Float = 0, hi: Float = 0
        vDSP_minv(values, 1, &lo, vDSP_Length(values.count))
        vDSP_maxv(values, 1, &hi, vDSP_Length(values.count))
        minimum = lo
        maximum = hi
        // Percentiles from a histogram of a sample of the pixels.
        let bins = 1024
        var histogram = [Int](repeating: 0, count: bins)
        let step = max(1, values.count / 65536)
        let scale = Float(bins - 1) / max(hi - lo, 1e-6)
        var n = 0
        for i in stride(from: 0, to: values.count, by: step) {
            histogram[Int((values[i] - lo) * scale)] += 1
            n += 1
        }
        func percentile(_ p: Double) -> Float {
            let target = Int(Double(n) * p)
            var sum = 0
            for (i, count) in histogram.enumerated() {
                sum += count
                if sum > target { return lo + Float(i) / scale }
            }
            return hi
        }
        low = percentile(0.01)
        high = max(percentile(0.99), low + 1e-3)
    }

    var isColor: Bool {
        if case .rgb = pixels { return true }
        return false
    }

    /// Draws the frame through a window (greyscale only), white for high values unless
    /// `invert`.
    func render(center: Double, width windowWidth: Double, invert: Bool) -> CGImage? {
        let count = width * height
        switch pixels {
        case .rgb(let rgb):
            return Self.image(Data(rgb), width: width, height: height, bytesPerPixel: 3,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!)
        case .gray(let values):
            let w = Float(max(windowWidth, 1e-6)), lo = Float(center) - w / 2
            var a = 255 / w, b = -lo * 255 / w
            if invert { (a, b) = (-a, 255 - b) }
            var scaled = [Float](repeating: 0, count: count)
            vDSP_vsmsa(values, 1, &a, &b, &scaled, 1, vDSP_Length(count))
            var floor: Float = 0, ceiling: Float = 255
            vDSP_vclip(scaled, 1, &floor, &ceiling, &scaled, 1, vDSP_Length(count))
            var bytes = Data(count: count)
            bytes.withUnsafeMutableBytes { out in
                vDSP_vfixru8(scaled, 1, out.bindMemory(to: UInt8.self).baseAddress!, 1, vDSP_Length(count))
            }
            return Self.image(bytes, width: width, height: height, bytesPerPixel: 1,
                              space: CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)!)
        }
    }

    private static func image(_ data: Data, width: Int, height: Int, bytesPerPixel: Int, space: CGColorSpace) -> CGImage? {
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8 * bytesPerPixel,
                       bytesPerRow: width * bytesPerPixel, space: space, bitmapInfo: CGBitmapInfo(rawValue: 0),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// A frame's samples before scaling: integers in file order, or RGB a codec already made.
enum DecodedSamples {
    case integers([Int32])
    case rgb([UInt8])
}

enum PixelError: LocalizedError {
    case short
    case unsupported(String)
    case cannotDecode(String)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .short: "The pixel data is shorter than the image size says."
        case .unsupported(let syntax): "The pixels are compressed as \(TransferSyntax.name(syntax)), which DICOM Viewer can’t decompress."
        case .cannotDecode(let syntax): "macOS couldn’t decode the \(TransferSyntax.name(syntax)) pixel data."
        case .message(let text): text
        }
    }
}

extension DicomFile {
    /// Decodes one frame, applying the rescale or modality LUT to greyscale pixels.
    func decode(frame f: Int) throws -> DecodedFrame {
        guard let image else { throw PixelError.message("This file has no image.") }
        let n = image.rows * image.columns
        let info = image.frames[min(f, image.frames.count - 1)]

        let samples: DecodedSamples
        if image.pixels.fragments == nil {
            samples = .integers(try uncompressed(image, frame: f))
        } else {
            let bytes = try encapsulatedBytes(image, frame: f)
            if transferSyntax == TransferSyntax.rle {
                samples = .integers(try rle(bytes, image))
            } else if TransferSyntax.imageIO.contains(transferSyntax) {
                guard let decoded = decodeWithImageIO(bytes, image) else { throw PixelError.cannotDecode(transferSyntax) }
                samples = decoded
            } else {
                throw PixelError.unsupported(transferSyntax)
            }
        }

        switch samples {
        case .rgb(let rgb):
            return DecodedFrame(width: image.columns, height: image.rows, pixels: .rgb(rgb))
        case .integers(let values) where image.isColor:
            return DecodedFrame(width: image.columns, height: image.rows, pixels: .rgb(color(values, image, pixels: n)))
        case .integers(let values):
            var out = [Float](repeating: 0, count: n)
            if let lut = image.modalityLUT {
                for i in 0..<n { out[i] = lut(Int(values[i])) }
            } else {
                vDSP_vflt32(values, 1, &out, 1, vDSP_Length(n))
                var slope = Float(info.slope), intercept = Float(info.intercept)
                if slope != 1 || intercept != 0 { vDSP_vsmsa(out, 1, &slope, &intercept, &out, 1, vDSP_Length(n)) }
            }
            return DecodedFrame(width: image.columns, height: image.rows, pixels: .gray(out))
        }
    }

    /// Raw samples of an uncompressed frame, masked to Bits Stored and sign-extended.
    private func uncompressed(_ image: ImageInfo, frame f: Int) throws -> [Int32] {
        let element = image.pixels
        let n = image.rows * image.columns * image.samples
        var out = [Int32](repeating: 0, count: n)
        try element.source.data.withUnsafeBytes { raw in
            let end = element.offset + element.length
            if image.bitsAllocated == 1 {
                let first = f * n
                guard element.offset + (first + n + 7) / 8 <= end else { throw PixelError.short }
                for i in 0..<n {
                    let bit = first + i
                    out[i] = Int32(raw[element.offset + bit >> 3] >> (bit & 7) & 1)
                }
                return
            }
            let size = image.bitsAllocated / 8
            guard [1, 2, 4].contains(size) else { throw PixelError.message("\(image.bitsAllocated)-bit pixels aren’t supported.") }
            let start = element.offset + f * n * size
            guard start + n * size <= end else { throw PixelError.short }
            let reader = Reader(bytes: raw, source: element.source, littleEndian: !element.bigEndian, explicit: true)
            switch size {
            case 1:
                for i in 0..<n { out[i] = image.signed ? Int32(Int8(bitPattern: raw[start + i])) : Int32(raw[start + i]) }
            case 2:
                for i in 0..<n {
                    let v = reader.u16(start + 2 * i)
                    out[i] = image.signed ? Int32(Int16(bitPattern: v)) : Int32(v)
                }
            default:
                for i in 0..<n { out[i] = Int32(truncatingIfNeeded: reader.u32(start + 4 * i)) }
            }
        }
        mask(&out, image)
        return out
    }

    /// Keeps the Bits Stored low bits of each sample, sign-extending signed ones.
    private func mask(_ values: inout [Int32], _ image: ImageInfo) {
        guard image.bitsStored < image.bitsAllocated, image.bitsAllocated > 1, !image.isColor else { return }
        let mask = Int32((1 << image.bitsStored) - 1), sign = Int32(1 << (image.bitsStored - 1))
        for i in values.indices {
            var v = values[i] & mask
            if image.signed && v >= sign { v -= 2 * sign }
            values[i] = v
        }
    }

    /// The bytes of one encapsulated frame: its fragments, found by the offset table, or
    /// one fragment per frame.
    private func encapsulatedBytes(_ image: ImageInfo, frame f: Int) throws -> Data {
        let all = image.pixels.fragments ?? []
        let data = all.dropFirst()
        let bytes = image.pixels.source.data
        func join(_ list: some Collection<Range<Int>>) -> Data {
            if list.count == 1, let only = list.first { return bytes[only] }
            var out = Data()
            for range in list { out.append(bytes[range]) }
            return out
        }
        guard let firstData = data.first else { throw PixelError.message("The encapsulated pixel data has no fragments.") }
        if image.frameCount == 1 { return join(data) }
        let table = all[0]
        if table.count >= 4 * image.frameCount {
            let base = firstData.lowerBound - 8
            let offsets = DicomFile.binaryNumbers(
                DicomElement(tag: 0, vr: "UL", offset: table.lowerBound, length: table.count, bigEndian: false, source: image.pixels.source),
                vr: "UL") ?? []
            let start = base + Int(offsets[f]), end = f + 1 < image.frameCount ? base + Int(offsets[f + 1]) : Int.max
            let list = data.filter { $0.lowerBound - 8 >= start && $0.lowerBound - 8 < end }
            if !list.isEmpty { return join(list) }
        }
        if data.count == image.frameCount { return join([data[data.startIndex + f]]) }
        throw PixelError.message("Can’t tell which fragments belong to which frame.")
    }

    /// RLE Lossless: one PackBits segment per byte of each sample, most significant first.
    private func rle(_ bytes: Data, _ image: ImageInfo) throws -> [Int32] {
        let size = image.bitsAllocated / 8, n = image.rows * image.columns
        return try bytes.withUnsafeBytes { raw in
            guard raw.count >= 64 else { throw PixelError.short }
            let segments = Int(UInt32(littleEndian: raw.loadUnaligned(as: UInt32.self)))
            guard segments == image.samples * size, [1, 2, 4].contains(size) else {
                throw PixelError.message("The RLE frame has \(segments) segments; \(image.samples * size) were expected.")
            }
            let offsets = (0..<segments).map { Int(UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: 4 + 4 * $0, as: UInt32.self))) }
            var planes = [[UInt8]](repeating: [], count: segments)
            for s in 0..<segments {
                planes[s] = DicomFile.unpackBits(raw, from: offsets[s], to: s + 1 < segments ? offsets[s + 1] : raw.count, count: n)
            }
            var out = [Int32](repeating: 0, count: n * image.samples)
            for sample in 0..<image.samples {
                for p in 0..<n {
                    var v: UInt32 = 0
                    for b in 0..<size { v = v << 8 | UInt32(planes[sample * size + b][p]) }
                    let value: Int32
                    switch (size, image.signed) {
                    case (1, true): value = Int32(Int8(truncatingIfNeeded: v))
                    case (2, true): value = Int32(Int16(truncatingIfNeeded: v))
                    default: value = Int32(truncatingIfNeeded: v)
                    }
                    out[p * image.samples + sample] = value
                }
            }
            mask(&out, image)
            return out
        }
    }

    private static func unpackBits(_ raw: UnsafeRawBufferPointer, from start: Int, to end: Int, count: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: count)
        var i = start, o = 0
        let end = min(end, raw.count)
        while i < end && o < count {
            let header = Int(Int8(bitPattern: raw[i]))
            i += 1
            if header >= 0 {
                let k = min(header + 1, count - o, end - i)
                for j in 0..<max(k, 0) { out[o + j] = raw[i + j] }
                i += header + 1
                o += max(k, 0)
            } else if header != -128, i < end {
                let k = min(1 - header, count - o)
                for j in 0..<k { out[o + j] = raw[i] }
                i += 1
                o += k
            }
        }
        return out
    }

    /// Decodes a JPEG or JPEG 2000 frame with ImageIO. The pixels are drawn into a bitmap
    /// in the image's own colour space, so the values aren't colour-matched on the way.
    private func decodeWithImageIO(_ bytes: Data, _ image: ImageInfo) -> DecodedSamples? {
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil),
              decoded.width == image.columns, decoded.height == image.rows else { return nil }
        let w = decoded.width, h = decoded.height
        let gray = decoded.colorSpace?.model == .monochrome
        if gray && !image.isColor {
            let deep = decoded.bitsPerComponent > 8
            let space = decoded.colorSpace ?? CGColorSpaceCreateDeviceGray()
            guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: deep ? 16 : 8,
                                          bytesPerRow: 0, space: space,
                                          bitmapInfo: deep ? CGImageByteOrderInfo.order16Little.rawValue : 0),
                  let base = context.data else { return nil }
            context.draw(decoded, in: CGRect(x: 0, y: 0, width: w, height: h))
            let row = context.bytesPerRow
            var out = [Int32](repeating: 0, count: w * h)
            for y in 0..<h {
                for x in 0..<w {
                    if deep {
                        let v = base.load(fromByteOffset: y * row + 2 * x, as: UInt16.self)
                        out[y * w + x] = image.signed ? Int32(Int16(bitPattern: v)) : Int32(v)
                    } else {
                        out[y * w + x] = Int32(base.load(fromByteOffset: y * row + x, as: UInt8.self))
                    }
                }
            }
            return .integers(out)
        }
        let space = decoded.colorSpace?.model == .rgb ? decoded.colorSpace! : CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let base = context.data else { return nil }
        context.draw(decoded, in: CGRect(x: 0, y: 0, width: w, height: h))
        let row = context.bytesPerRow
        var rgb = [UInt8](repeating: 0, count: w * h * 3)
        for y in 0..<h {
            for x in 0..<w {
                for c in 0..<3 { rgb[(y * w + x) * 3 + c] = base.load(fromByteOffset: y * row + 4 * x + c, as: UInt8.self) }
            }
        }
        return .rgb(rgb)
    }

    /// Interleaved 8-bit RGB from colour samples: planar or not, YBR_FULL, or a palette.
    private func color(_ values: [Int32], _ image: ImageInfo, pixels n: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: n * 3)
        if image.photometric == "PALETTE COLOR" {
            let palette = (0..<3).map { paletteLUT(channel: $0) }
            for i in 0..<n {
                for c in 0..<3 {
                    if let lut = palette[c] {
                        out[i * 3 + c] = lut.values[min(max(Int(values[i]) - lut.first, 0), lut.values.count - 1)]
                    } else {
                        out[i * 3 + c] = UInt8(clamping: values[i])
                    }
                }
            }
            return out
        }
        let shift = image.bitsAllocated > 8 ? Int32(image.bitsStored - 8) : 0
        for i in 0..<n {
            for c in 0..<3 {
                let v = image.planar == 1 ? values[c * n + i] : values[i * 3 + c]
                out[i * 3 + c] = UInt8(clamping: shift > 0 ? v >> shift : v)
            }
        }
        if image.photometric.hasPrefix("YBR_FULL") {
            for i in stride(from: 0, to: n * 3, by: 3) {
                let y = Double(out[i]), cb = Double(out[i + 1]) - 128, cr = Double(out[i + 2]) - 128
                out[i] = UInt8(clamping: Int((y + 1.402 * cr).rounded()))
                out[i + 1] = UInt8(clamping: Int((y - 0.344136 * cb - 0.714136 * cr).rounded()))
                out[i + 2] = UInt8(clamping: Int((y + 1.772 * cb).rounded()))
            }
        }
        return out
    }

    private func paletteLUT(channel c: Int) -> (first: Int, values: [UInt8])? {
        let shift = UInt32(c)
        guard let descriptor = numbers(0x0028_1101 + shift), descriptor.count >= 3,
              let element = dataSet[0x0028_1201 + shift] else { return nil }
        let count = descriptor[0] == 0 ? 65536 : Int(descriptor[0])
        let words = DicomFile.binaryNumbers(element, vr: "US", max: count) ?? []
        let values = (0..<count).map { k -> UInt8 in
            let v = k < words.count ? UInt16(words[k]) : 0
            return descriptor[2] == 16 ? UInt8(v >> 8) : UInt8(v & 0xFF)
        }
        return (Int(descriptor[1]), values)
    }
}
