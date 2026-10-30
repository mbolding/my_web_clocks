// DicomFile — reads a DICOM file's elements: the file meta group, then the data set in
// its transfer syntax (explicit or implicit VR, little or big endian, or deflated), with
// sequences and encapsulated pixel data. A port of the parser in dicom/index.html.
// Values stay in the file's bytes until asked for; the pixel data is only located.

import Foundation
import Compression

enum TransferSyntax {
    static let implicitLittle = "1.2.840.10008.1.2"
    static let explicitLittle = "1.2.840.10008.1.2.1"
    static let deflated = "1.2.840.10008.1.2.1.99"
    static let explicitBig = "1.2.840.10008.1.2.2"
    static let rle = "1.2.840.10008.1.2.5"
    static let jpegBaseline = "1.2.840.10008.1.2.4.50"

    /// Compressed syntaxes ImageIO may decode. Only baseline JPEG is sure to work; the
    /// others are tried and reported if they fail.
    static let imageIO: Set<String> = [
        jpegBaseline, "1.2.840.10008.1.2.4.51",
        "1.2.840.10008.1.2.4.90", "1.2.840.10008.1.2.4.91",
        "1.2.840.10008.1.2.4.201", "1.2.840.10008.1.2.4.202", "1.2.840.10008.1.2.4.203",
    ]

    static func name(_ uid: String) -> String { TagDictionary.uids[uid] ?? uid }
}

/// The bytes elements point into: the file itself, or the inflated data set of a
/// deflated file.
final class ByteSource: @unchecked Sendable {
    let data: Data
    init(_ data: Data) { self.data = data }
}

struct DicomElement {
    let tag: UInt32
    var vr: String
    /// Where the value starts in `source`, and its length in bytes.
    let offset: Int
    var length: Int
    let bigEndian: Bool
    let source: ByteSource
    /// A sequence's items.
    var items: [DataSet]?
    /// Encapsulated pixel data: the byte range of each fragment, the offset table first.
    var fragments: [Range<Int>]?

    var group: UInt16 { UInt16(tag >> 16) }
    var element: UInt16 { UInt16(tag & 0xFFFF) }
    var isPrivate: Bool { group & 1 == 1 }
    var bytes: Data { source.data[offset..<(offset + length)] }
}

/// Elements in file order, with a lookup by tag.
struct DataSet {
    let elements: [DicomElement]
    private let index: [UInt32: Int]

    init(_ elements: [DicomElement]) {
        self.elements = elements
        var index: [UInt32: Int] = [:]
        for (i, element) in elements.enumerated() where index[element.tag] == nil { index[element.tag] = i }
        self.index = index
    }

    subscript(tag: UInt32) -> DicomElement? { index[tag].map { elements[$0] } }
}

enum Tag {
    static let item: UInt32 = 0xFFFE_E000
    static let itemEnd: UInt32 = 0xFFFE_E00D
    static let sequenceEnd: UInt32 = 0xFFFE_E0DD
    static let pixelData: UInt32 = 0x7FE0_0010
}

final class DicomFile: Identifiable, @unchecked Sendable {
    let url: URL
    let size: Int
    let meta: DataSet
    let dataSet: DataSet
    let transferSyntax: String
    /// The file ends before an element it starts, or an element's length runs past it.
    let truncated: Bool
    let encoding: String.Encoding
    /// The pixel data's layout and each frame's scaling and position, if it has an image.
    private(set) var image: ImageInfo?

    var id: URL { url }
    var name: String { url.lastPathComponent }

    enum ReadError: LocalizedError {
        case notDicom
        var errorDescription: String? { "Not a DICOM file" }
    }

    init(url: URL) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        self.url = url
        size = data.count

        let preamble = data.count >= 132 && data[128] == 0x44 && data[129] == 0x49 && data[130] == 0x43 && data[131] == 0x4D
        var position = preamble ? 132 : 0
        let fileSource = ByteSource(data)
        var truncated = false

        // The meta group is always explicit VR little endian.
        var metaElements: [DicomElement] = []
        data.withUnsafeBytes { raw in
            let reader = Reader(bytes: raw, source: fileSource, littleEndian: true, explicit: true)
            while position + 8 <= raw.count, reader.u16(position) == 0x0002 {
                guard var element = reader.head(at: position), element.length != Reader.undefined else { break }
                element.length = min(element.length, raw.count - element.offset)
                metaElements.append(element)
                position = element.offset + element.length
            }
        }
        meta = DataSet(metaElements)

        var syntax = DicomFile.text(meta[0x0002_0010], encoding: .isoLatin1).first ?? ""
        if syntax.isEmpty {
            // No transfer syntax: work it out from the first element. A bare data set (no
            // preamble) has to open with a low, even group number.
            guard data.count >= position + 16 else { throw ReadError.notDicom }
            let little = UInt16(data[position]) | UInt16(data[position + 1]) << 8
            let big = UInt16(data[position]) << 8 | UInt16(data[position + 1])
            let plausible = { (g: UInt16) in g % 2 == 0 && g >= 0x0002 && g <= 0x0028 }
            let le = plausible(little), be = !le && plausible(big)
            if !preamble && !le && !be { throw ReadError.notDicom }
            let vr = String(bytes: data[(position + 4)..<(position + 6)], encoding: .isoLatin1) ?? ""
            syntax = be ? TransferSyntax.explicitBig : Reader.validVRs.contains(vr) ? TransferSyntax.explicitLittle : TransferSyntax.implicitLittle
        }
        transferSyntax = syntax

        var body = fileSource, start = position
        if syntax == TransferSyntax.deflated {
            body = ByteSource(DicomFile.inflate(data[position...]))
            start = 0
        }
        var elements: [DicomElement] = []
        body.data.withUnsafeBytes { raw in
            let reader = Reader(bytes: raw, source: body, littleEndian: syntax != TransferSyntax.explicitBig,
                                explicit: syntax != TransferSyntax.implicitLittle)
            elements = reader.parseSet(from: start, to: raw.count, truncated: &truncated).elements
        }
        if elements.isEmpty && metaElements.isEmpty { throw ReadError.notDicom }
        // A bare data set is only a guess, so insist on a few elements in order.
        if !preamble && metaElements.isEmpty {
            let ordered = zip(elements, elements.dropFirst()).allSatisfy { $0.tag < $1.tag }
            if elements.count < 3 || !ordered { throw ReadError.notDicom }
        }
        dataSet = DataSet(elements)
        self.truncated = truncated

        let charsets = DicomFile.text(dataSet[0x0008_0005], encoding: .isoLatin1).filter { !$0.isEmpty }
        encoding = (charsets.last).flatMap(DicomFile.encoding(named:)) ?? charsets.first.flatMap(DicomFile.encoding(named:)) ?? .isoLatin1

        image = ImageInfo(file: self)
    }

    // MARK: Values

    /// The element's values as strings, for the string VRs.
    func strings(_ element: DicomElement?) -> [String] {
        guard let element else { return [] }
        let personal: Set<String> = ["LO", "LT", "PN", "SH", "ST", "UC", "UT"]
        return DicomFile.text(element, encoding: personal.contains(element.vr) ? encoding : .isoLatin1)
    }

    func string(_ tag: UInt32, in set: DataSet? = nil) -> String {
        strings((set ?? dataSet)[tag]).joined(separator: "\\")
    }

    /// Numbers from a numeric binary VR, or from a DS or IS string.
    func numbers(_ element: DicomElement?, max: Int = .max) -> [Double]? {
        guard let element, element.items == nil else { return nil }
        if element.vr == "DS" || element.vr == "IS" {
            let values = strings(element).compactMap { Double($0) }
            return values.isEmpty ? nil : values
        }
        guard let values = DicomFile.binaryNumbers(element, vr: element.vr, max: max), !values.isEmpty else { return nil }
        return values
    }

    func numbers(_ tag: UInt32, in set: DataSet? = nil) -> [Double]? { numbers((set ?? dataSet)[tag]) }

    func number(_ tag: UInt32, in set: DataSet? = nil) -> Double? { numbers(tag, in: set)?.first }

    static let textVRs: Set<String> = ["LT", "ST", "UT", "UR"]
    static let stringVRs: Set<String> = ["AE", "AS", "CS", "DA", "DS", "DT", "IS", "LO", "LT", "PN", "SH", "ST", "TM", "UC", "UI", "UR", "UT"]
    static let numberSizes: [String: Int] = ["US": 2, "SS": 2, "UL": 4, "SL": 4, "FL": 4, "FD": 8, "SV": 8, "UV": 8]

    static func text(_ element: DicomElement?, encoding: String.Encoding) -> [String] {
        guard let element, element.items == nil, element.fragments == nil else { return [] }
        var string = String(data: element.bytes, encoding: encoding) ?? String(decoding: element.bytes, as: UTF8.self)
        while let last = string.last, last == "\0" || last == " " { string.removeLast() }
        if textVRs.contains(element.vr) { return [string] }
        if string.isEmpty { return [] }
        return string.split(separator: "\\", omittingEmptySubsequences: false).map {
            $0.replacingOccurrences(of: "\0", with: "").trimmingCharacters(in: .whitespaces)
        }
    }

    static func binaryNumbers(_ element: DicomElement, vr: String, max: Int = .max) -> [Double]? {
        guard let size = numberSizes[vr] else { return nil }
        let count = Swift.min(element.length / size, max)
        return element.source.data.withUnsafeBytes { raw in
            let reader = Reader(bytes: raw, source: element.source, littleEndian: !element.bigEndian, explicit: true)
            return (0..<count).map { i -> Double in
                let at = element.offset + i * size
                switch vr {
                case "US": return Double(reader.u16(at))
                case "SS": return Double(Int16(bitPattern: reader.u16(at)))
                case "UL": return Double(reader.u32(at))
                case "SL": return Double(Int32(bitPattern: reader.u32(at)))
                case "FL": return Double(Float(bitPattern: reader.u32(at)))
                case "FD": return Double(bitPattern: reader.u64(at))
                case "SV": return Double(Int64(bitPattern: reader.u64(at)))
                default: return Double(reader.u64(at))
                }
            }
        }
    }

    /// Attribute tags, for the AT VR, as "(0010,0010)".
    static func tags(_ element: DicomElement, max: Int = .max) -> [String] {
        element.source.data.withUnsafeBytes { raw in
            let reader = Reader(bytes: raw, source: element.source, littleEndian: !element.bigEndian, explicit: true)
            return stride(from: 0, to: element.length - 3, by: 4).prefix(max).map { i in
                format(tag: UInt32(reader.u16(element.offset + i)) << 16 | UInt32(reader.u16(element.offset + i + 2)))
            }
        }
    }

    static func format(tag: UInt32) -> String {
        String(format: "(%04X,%04X)", tag >> 16, tag & 0xFFFF)
    }

    /// Specific Character Set terms, as in dicom/index.html, by their IANA names.
    private static func encoding(named term: String) -> String.Encoding? {
        let names = [
            "ISO_IR 6": "iso-8859-1", "ISO_IR 100": "iso-8859-1", "ISO_IR 101": "iso-8859-2", "ISO_IR 109": "iso-8859-3",
            "ISO_IR 110": "iso-8859-4", "ISO_IR 144": "iso-8859-5", "ISO_IR 127": "iso-8859-6", "ISO_IR 126": "iso-8859-7",
            "ISO_IR 138": "iso-8859-8", "ISO_IR 148": "iso-8859-9", "ISO_IR 13": "shift_jis", "ISO_IR 166": "tis-620",
            "ISO_IR 192": "utf-8", "GB18030": "gb18030", "GBK": "gbk", "ISO 2022 IR 87": "iso-2022-jp",
            "ISO 2022 IR 149": "euc-kr", "ISO 2022 IR 58": "gb2312",
        ]
        guard let name = names[term.trimmingCharacters(in: .whitespaces)] else { return nil }
        let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard cf != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
    }

    /// Inflates a raw deflate stream, keeping what came out before any error: writers pad
    /// deflated data to an even length, and the trailing byte can upset the inflater.
    private static func inflate(_ input: Data) -> Data {
        var output = Data()
        let chunk = 1 << 20
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer { buffer.deallocate() }
        var stream = compression_stream(dst_ptr: buffer, dst_size: chunk, src_ptr: buffer, src_size: 0, state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else { return output }
        defer { compression_stream_destroy(&stream) }
        input.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            stream.src_ptr = base
            stream.src_size = raw.count
            while true {
                stream.dst_ptr = buffer
                stream.dst_size = chunk
                let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                output.append(buffer, count: chunk - stream.dst_size)
                if status != COMPRESSION_STATUS_OK { break }
            }
        }
        return output
    }
}

/// Reads element headers and values from a buffer in one byte order and VR mode.
struct Reader {
    let bytes: UnsafeRawBufferPointer
    let source: ByteSource
    let littleEndian: Bool
    var explicit: Bool

    static let undefined = Int(UInt32.max)
    static let validVRs: Set<String> = ["AE", "AS", "AT", "CS", "DA", "DS", "DT", "FD", "FL", "IS", "LO", "LT", "OB", "OD", "OF", "OL",
                                        "OV", "OW", "PN", "SH", "SL", "SQ", "SS", "ST", "SV", "TM", "UC", "UI", "UL", "UN", "UR", "US", "UT", "UV"]
    private static let longVRs: Set<String> = ["OB", "OD", "OF", "OL", "OV", "OW", "SQ", "SV", "UC", "UN", "UR", "UT", "UV"]

    func u16(_ i: Int) -> UInt16 {
        let v = bytes.loadUnaligned(fromByteOffset: i, as: UInt16.self)
        return littleEndian ? UInt16(littleEndian: v) : UInt16(bigEndian: v)
    }

    func u32(_ i: Int) -> UInt32 {
        let v = bytes.loadUnaligned(fromByteOffset: i, as: UInt32.self)
        return littleEndian ? UInt32(littleEndian: v) : UInt32(bigEndian: v)
    }

    func u64(_ i: Int) -> UInt64 {
        let v = bytes.loadUnaligned(fromByteOffset: i, as: UInt64.self)
        return littleEndian ? UInt64(littleEndian: v) : UInt64(bigEndian: v)
    }

    func tag(at p: Int) -> UInt32 { UInt32(u16(p)) << 16 | UInt32(u16(p + 2)) }

    /// The element header at `p`, or nil if it runs off the end.
    func head(at p: Int) -> DicomElement? {
        guard p + 8 <= bytes.count else { return nil }
        let tag = tag(at: p)
        func element(_ vr: String, _ length: Int, _ offset: Int) -> DicomElement {
            DicomElement(tag: tag, vr: vr, offset: offset, length: length, bigEndian: !littleEndian, source: source)
        }
        if tag >> 16 == 0xFFFE { return element("", Int(u32(p + 4)), p + 8) }
        if explicit {
            let vr = String(decoding: [bytes[p + 4], bytes[p + 5]], as: UTF8.self)
            if Reader.validVRs.contains(vr) {
                if Reader.longVRs.contains(vr) {
                    guard p + 12 <= bytes.count else { return nil }
                    return element(vr, Int(u32(p + 8)), p + 12)
                }
                return element(vr, Int(u16(p + 6)), p + 8)
            }
        }
        // Implicit VR, or an explicit file that slipped into implicit: the VR comes from
        // the dictionary.
        return element(TagDictionary.vr(for: tag), Int(u32(p + 4)), p + 8)
    }

    private func startsWithItem(_ offset: Int, _ end: Int) -> Bool {
        offset + 8 <= end && u16(offset) == 0xFFFE && u16(offset + 2) == 0xE000
    }

    /// Parses elements from `p` to `end`. Inside an item of undefined length it stops at
    /// the item delimiter and returns the position after it.
    func parseSet(from start: Int, to end: Int, truncated: inout Bool) -> (elements: [DicomElement], next: Int) {
        var elements: [DicomElement] = []
        var p = start
        while p + 8 <= end {
            let implicitHere = !explicit || !Reader.validVRs.contains(String(decoding: [bytes[p + 4], bytes[p + 5]], as: UTF8.self))
            guard var element = head(at: p) else { truncated = true; break }
            if element.tag == Tag.itemEnd || element.tag == Tag.sequenceEnd || element.tag == Tag.item {
                return (elements, element.offset)
            }
            let implicitElement = implicitHere && element.group != 0xFFFE
            var asSequence = element.vr == "SQ"
            if !asSequence && element.tag != Tag.pixelData && (element.vr == "UN" || implicitElement) {
                asSequence = element.length == Reader.undefined || startsWithItem(element.offset, min(end, element.offset + element.length))
            }
            let next: Int
            if asSequence {
                // UN with an undefined length holds an implicit little endian sequence.
                var reader = self
                if element.vr == "UN" && !implicitElement {
                    reader = Reader(bytes: bytes, source: source, littleEndian: true, explicit: false)
                }
                let (items, after) = reader.parseSequence(at: element.offset, length: element.length, outerEnd: end, truncated: &truncated)
                element.vr = "SQ"
                element.items = items
                next = after
            } else if element.length == Reader.undefined {
                let (fragments, after) = parseFragments(at: element.offset, end: end)
                element.fragments = fragments
                element.length = after - element.offset
                next = after
            } else if element.offset + element.length > end {
                element.length = max(0, end - element.offset)
                truncated = true
                next = end
            } else {
                next = element.offset + element.length
            }
            elements.append(element)
            p = next
        }
        return (elements, max(p, end))
    }

    private func parseSequence(at offset: Int, length: Int, outerEnd: Int, truncated: inout Bool) -> ([DataSet], Int) {
        let end = length == Reader.undefined ? outerEnd : min(offset + length, outerEnd)
        var items: [DataSet] = []
        var p = offset
        while p + 8 <= end {
            let tag = tag(at: p), itemLength = Int(u32(p + 4))
            if tag == Tag.sequenceEnd { p += 8; break }
            if tag != Tag.item { break }
            p += 8
            if itemLength == Reader.undefined {
                let (elements, next) = parseSet(from: p, to: end, truncated: &truncated)
                items.append(DataSet(elements))
                p = next
            } else {
                let itemEnd = min(p + itemLength, end)
                items.append(DataSet(parseSet(from: p, to: itemEnd, truncated: &truncated).elements))
                p = itemEnd
            }
        }
        return (items, length == Reader.undefined ? p : end)
    }

    private func parseFragments(at start: Int, end: Int) -> ([Range<Int>], Int) {
        var fragments: [Range<Int>] = []
        var p = start
        while p + 8 <= end {
            let tag = tag(at: p), length = Int(u32(p + 4))
            p += 8
            if tag == Tag.sequenceEnd { break }
            if tag != Tag.item || length == Reader.undefined { break }
            fragments.append(p..<min(p + length, end))
            p += length
        }
        return (fragments, min(p, end))
    }
}
