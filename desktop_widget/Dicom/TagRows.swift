// TagRows — a file's elements as rows for the tag list: the meta group, then the data
// set, with each sequence's items and their elements indented beneath it. Values are
// written out as in dicom/index.html: strings and numbers as they are, UIDs with their
// names, and binary data as a short run of hex.

import Foundation

struct TagRow: Identifiable {
    let id: Int
    let depth: Int
    let tag: String
    let name: String
    let vr: String
    let value: String
    /// Lower-cased text the search field matches against.
    let search: String

    /// "(0010,0010) PatientName PN Doe John", for copying.
    var line: String {
        String(repeating: "  ", count: depth) + [tag, name, vr, value].filter { !$0.isEmpty }.joined(separator: "  ")
    }
}

enum TagRows {
    static func rows(for file: DicomFile) -> [TagRow] {
        var rows: [TagRow] = []
        func add(depth: Int, tag: String, name: String, vr: String, value: String) {
            rows.append(TagRow(id: rows.count, depth: depth, tag: tag, name: name, vr: vr, value: value,
                               search: [tag, name, vr, value].joined(separator: " ").lowercased()))
        }
        func walk(_ set: DataSet, depth: Int) {
            for element in set.elements {
                add(depth: depth, tag: DicomFile.format(tag: element.tag), name: name(of: element, in: set, file: file),
                    vr: element.vr, value: value(of: element, file: file))
                for (i, item) in (element.items ?? []).enumerated() {
                    add(depth: depth + 1, tag: "", name: "Item \(i + 1)", vr: "",
                        value: Series.count(item.elements.count, "element"))
                    walk(item, depth: depth + 2)
                }
            }
        }
        walk(file.meta, depth: 0)
        walk(file.dataSet, depth: 0)
        return rows
    }

    static func name(of element: DicomElement, in set: DataSet, file: DicomFile) -> String {
        if let entry = TagDictionary.tags[element.tag] { return entry.keyword }
        let group = element.group, e = element.element
        if e == 0 { return "GroupLength" }
        if group & 0xFF01 == 0x6000, let entry = TagDictionary.overlay[e] { return entry.keyword }
        if element.isPrivate {
            if (0x10...0xFF).contains(e) { return "PrivateCreator" }
            if e >= 0x1000 {
                let creator = file.string(UInt32(group) << 16 | UInt32(e >> 8), in: set)
                return creator.isEmpty ? "Private" : "Private · \(creator)"
            }
            return "Private"
        }
        return "Unknown"
    }

    static func value(of element: DicomElement, file: DicomFile) -> String {
        if let items = element.items { return Series.count(items.count, "item") }
        if let fragments = element.fragments {
            let total = fragments.reduce(0) { $0 + $1.count }
            return "Encapsulated, \(Series.count(fragments.count, "fragment")) (\(size(total)))"
        }
        if [Tag.pixelData, 0x7FE0_0008, 0x7FE0_0009].contains(element.tag) { return "\(size(element.length)) of pixel data" }

        var vr = element.vr
        if vr == "UN", let entry = TagDictionary.tags[element.tag], entry.vr != "UN", entry.vr != "SQ" { vr = entry.vr }
        var text: String
        if DicomFile.stringVRs.contains(vr) {
            let values = DicomFile.text(element, encoding: ["LO", "LT", "PN", "SH", "ST", "UC", "UT"].contains(vr) ? file.encoding : .isoLatin1)
            text = values.joined(separator: " \\ ")
            if vr == "UI", let first = values.first, let name = TagDictionary.uids[first] { text += "  — \(name)" }
        } else if vr == "AT" {
            text = DicomFile.tags(element, max: 64).joined(separator: " \\ ")
        } else if let size = DicomFile.numberSizes[vr], let numbers = DicomFile.binaryNumbers(element, vr: vr, max: 64) {
            text = numbers.map(format).joined(separator: " \\ ")
            if element.length / size > numbers.count { text += " … (\(element.length / size) values)" }
        } else {
            let bytes = element.bytes
            if vr == "UN", bytes.count <= 4096, printable(bytes) {
                text = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
            } else {
                text = bytes.prefix(24).map { String(format: "%02x", $0) }.joined(separator: " ")
                    + (bytes.count > 24 ? " …" : "") + " (\(size(bytes.count)))"
            }
        }
        return text.count > 300 ? String(text.prefix(300)) + "…" : text
    }

    private static func format(_ x: Double) -> String {
        guard x.isFinite else { return "\(x)" }
        if x == x.rounded() && abs(x) < 1e15 { return String(Int64(x)) }
        return String(format: "%.6g", x)
    }

    static func size(_ n: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }

    private static func printable(_ bytes: Data) -> Bool {
        guard !bytes.isEmpty else { return false }
        for (i, b) in bytes.enumerated() {
            if b == 0 && i == bytes.count - 1 { continue }
            if (b < 32 && b != 9 && b != 10 && b != 13) || (b > 126 && b < 160) { return false }
        }
        return true
    }
}
