// Series — gathers the DICOM files from what was opened or dropped (folders are searched
// all the way down, and anything that isn't DICOM is skipped by its contents, not its
// name), groups them by Series Instance UID and image size, and puts each series' slices
// in order: by Instance Number, then by position along the slice normal, then by name.
// A multi-frame file's frames are slices too.

import Foundation
import CoreGraphics

struct Slice {
    let file: DicomFile
    let frame: Int
}

final class Series: Identifiable, @unchecked Sendable {
    let id: String
    let files: [DicomFile]
    let slices: [Slice]
    let title: String
    let modality: String
    let number: Int?
    let study: String
    let studyKey: String
    let sortKey: String
    let hasImage: Bool
    fileprivate(set) var part: Int?

    init(id: String, files: [DicomFile], slices: [Slice], hasImage: Bool) {
        self.id = id
        self.files = files
        self.slices = slices
        self.hasImage = hasImage
        let first = files[0]
        modality = first.string(0x0008_0060)
        number = first.number(0x0020_0011).map(Int.init)
        title = [0x0008_103E, 0x0018_1030].lazy.map { first.string($0) }.first { !$0.isEmpty }
            ?? TagDictionary.uids[first.string(0x0008_0016)] ?? first.name
        studyKey = first.string(0x0020_000D)
        let date = first.string(0x0008_0020)
        study = [Series.personName(first.string(0x0010_0010)), first.string(0x0008_1030), Series.format(date: date)]
            .filter { !$0.isEmpty }.joined(separator: " · ")
        sortKey = [date, first.string(0x0008_0030), studyKey].joined(separator: "|")
    }

    var displayTitle: String { part.map { "\(title) (part \($0))" } ?? title }

    /// Greyscale images, which have a window and level to change.
    var canWindow: Bool { hasImage && files[0].image?.isColor == false }

    /// "CT · 512×512 · 120 images"
    var subtitle: String {
        var bits = [modality]
        if hasImage, let image = files[0].image {
            bits.append("\(image.columns)×\(image.rows)")
            bits.append(Series.count(slices.count, "image"))
            if files.count > 1 && files.count != slices.count { bits.append(Series.count(files.count, "file")) }
        } else {
            bits.append("headers only")
            bits.append(Series.count(files.count, "file"))
        }
        return bits.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static func count(_ n: Int, _ noun: String) -> String { "\(n.formatted()) \(noun)\(n == 1 ? "" : "s")" }

    /// "Family^Given^Middle" as "Family Given Middle", leaving out any ideographic forms.
    static func personName(_ value: String) -> String {
        value.split(separator: "=").first.map { $0.split(separator: "^").joined(separator: " ") } ?? ""
    }

    static func format(date: String) -> String {
        guard date.count == 8 else { return date }
        let d = Array(date)
        return "\(String(d[0..<4]))-\(String(d[4..<6]))-\(String(d[6..<8]))"
    }
}

enum Loader {
    struct Result {
        var series: [Series] = []
        var files = 0
        var skipped = 0
    }

    /// Every regular file in the URLs, searching folders but skipping hidden files.
    static func files(in urls: [URL]) -> [URL] {
        var out: [URL] = []
        for url in urls {
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else { continue }
            guard isFolder.boolValue else { out.append(url); continue }
            let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey],
                                                        options: [.skipsHiddenFiles, .skipsPackageDescendants])
            while let file = walker?.nextObject() as? URL {
                if (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { out.append(file) }
            }
        }
        return out.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    static func load(_ urls: [URL], progress: @escaping @Sendable (Double) -> Void) -> Result {
        let paths = files(in: urls)
        var parsed = [DicomFile?](repeating: nil, count: paths.count)
        let lock = NSLock()
        var done = 0
        parsed.withUnsafeMutableBufferPointer { slots in
            let slots = slots
            DispatchQueue.concurrentPerform(iterations: paths.count) { i in
                slots[i] = try? DicomFile(url: paths[i])
                lock.lock()
                done += 1
                let report = done % 25 == 0
                let fraction = Double(done) / Double(paths.count)
                lock.unlock()
                if report { progress(fraction) }
            }
        }
        let files = parsed.compactMap { $0 }
        return Result(series: group(files), files: files.count, skipped: paths.count - files.count)
    }

    static func group(_ files: [DicomFile]) -> [Series] {
        var groups: [String: [DicomFile]] = [:]
        var order: [String] = []
        for file in files {
            let uid = file.string(0x0020_000E).isEmpty ? "file:" + file.url.path : file.string(0x0020_000E)
            let key: String
            if let image = file.image {
                key = [uid, "\(image.rows)", "\(image.columns)", "\(image.samples)"].joined(separator: "|")
            } else {
                key = uid + "|headers"
            }
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(file)
        }

        var series = order.map { key -> Series in
            let files = sorted(groups[key]!)
            let hasImage = files[0].image != nil
            let slices = hasImage
                ? files.flatMap { file in (0..<(file.image?.frameCount ?? 1)).map { Slice(file: file, frame: $0) } }
                : files.map { Slice(file: $0, frame: 0) }
            return Series(id: key, files: files, slices: slices, hasImage: hasImage)
        }

        // A series split by image size gets numbered parts.
        var parts: [String: Int] = [:]
        for s in series { parts[s.id.components(separatedBy: "|")[0], default: 0] += 1 }
        var seen: [String: Int] = [:]
        for s in series {
            let uid = s.id.components(separatedBy: "|")[0]
            if parts[uid]! > 1 {
                seen[uid, default: 0] += 1
                s.part = seen[uid]
            }
        }

        series.sort { a, b in
            if a.sortKey != b.sortKey { return a.sortKey < b.sortKey }
            if a.number != b.number { return (a.number ?? 0) < (b.number ?? 0) }
            return (a.part ?? 0) < (b.part ?? 0)
        }
        return series
    }

    /// Instance Number first, then position along the slice normal, then file name.
    private static func sorted(_ files: [DicomFile]) -> [DicomFile] {
        let keyed = files.map { file -> (DicomFile, Double?, Double?) in
            var along: Double?
            if let frame = file.image?.frames.first, let p = frame.position, let o = frame.orientation {
                let normal = [o[1] * o[5] - o[2] * o[4], o[2] * o[3] - o[0] * o[5], o[0] * o[4] - o[1] * o[3]]
                along = p[0] * normal[0] + p[1] * normal[1] + p[2] * normal[2]
            }
            return (file, file.number(0x0020_0013), along)
        }
        return keyed.sorted { a, b in
            if let x = a.1, let y = b.1, x != y { return x < y }
            if (a.1 == nil) != (b.1 == nil) { return a.1 != nil }
            if let x = a.2, let y = b.2, abs(x - y) > 1e-4 { return x < y }
            return a.0.name.localizedStandardCompare(b.0.name) == .orderedAscending
        }.map(\.0)
    }
}
