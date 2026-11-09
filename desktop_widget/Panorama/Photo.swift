// Photo — reading the pictures: their size the right way up, the lens's focal length and
// the time they were taken from their EXIF, and their pixels at whatever size is wanted.

import Foundation
import ImageIO
import CoreGraphics
import simd

typealias Mat3 = simd_double3x3

/// Pixels as red, green, blue and alpha bytes, row by row, kept in one allocation so the
/// render loops can read them without copying.
final class Bitmap: @unchecked Sendable {
    let width: Int, height: Int
    let data: UnsafeMutablePointer<UInt8>

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        data = .allocate(capacity: width * height * 4)
        data.initialize(repeating: 0, count: width * height * 4)
    }

    deinit { data.deallocate() }

    var bytes: Int { width * height * 4 }

    /// The pixels as a CGImage in the given colour space; transparent where alpha is 0.
    func image(colorSpace: CGColorSpace, opaque: Bool = false) -> CGImage? {
        let info = opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast
        guard let provider = CGDataProvider(data: Data(bytes: data, count: bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: info.rawValue), provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

struct Photo: Identifiable, Sendable, Equatable {
    let id = UUID()
    let url: URL
    /// Its size the right way up, in pixels.
    let width: Int, height: Int
    /// The focal length as on a 35 mm camera, when the EXIF says.
    let focal35: Double?
    let taken: Date?

    var name: String { url.lastPathComponent }
    var longSide: Int { max(width, height) }
    var diagonal: Double { Double(width * width + height * height).squareRoot() }

    static func == (a: Photo, b: Photo) -> Bool { a.id == b.id }

    /// Reads a photo's header; nil if it isn't a picture.
    static func read(_ url: URL) -> Photo? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              var width = props[kCGImagePropertyPixelWidth] as? Int,
              var height = props[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0
        else { return nil }
        if let orientation = props[kCGImagePropertyOrientation] as? Int, (5...8).contains(orientation) {
            swap(&width, &height)
        }
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        var focal = (exif[kCGImagePropertyExifFocalLenIn35mmFilm] as? NSNumber)?.doubleValue
        if focal == 0 { focal = nil }
        var taken: Date?
        if let text = exif[kCGImagePropertyExifDateTimeOriginal] as? String ?? exif[kCGImagePropertyExifDateTimeDigitized] as? String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            taken = formatter.date(from: text)
            if let sub = exif[kCGImagePropertyExifSubsecTimeOriginal] as? String, let fraction = Double("0." + sub) {
                taken = taken?.addingTimeInterval(fraction)
            }
        }
        return Photo(url: url, width: width, height: height, focal35: focal, taken: taken)
    }

    /// The pixels, the right way up, with the long side at most `maxSide`, drawn into the
    /// given colour space.
    func pixels(maxSide: Int, colorSpace: CGColorSpace) -> Bitmap? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxSide, longSide),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let bitmap = Bitmap(width: image.width, height: image.height)
        guard let context = CGContext(data: bitmap.data, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: image.width * 4, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bitmap
    }

    /// The colour space the photo was taken in, when it's an RGB one, for the panorama to
    /// keep; sRGB otherwise.
    var colorSpace: CGColorSpace {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary),
           let space = image.colorSpace, space.model == .rgb {
            return space
        }
        return CGColorSpace(name: CGColorSpace.sRGB)!
    }

    /// A small picture for the strip of photos.
    func thumbnail(side: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: side,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
