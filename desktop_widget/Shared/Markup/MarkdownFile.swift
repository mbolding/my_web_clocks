// MarkdownFile — the document Reveal Codes and Pilcrow both open: a Markdown or plain text
// file, read and written as it is on disk.

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Declared in InfoPlistExtras.xml, with its file extensions.
    static let markdown = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

/// A Markdown or plain text file, written back as it came: the same encoding, and a byte
/// order mark only if it had one. A reference type, so the editor's own undo is what marks
/// it edited.
final class MarkdownFile: ReferenceFileDocument {
    static var readableContentTypes: [UTType] { [.markdown, .plainText] }
    static var writableContentTypes: [UTType] { [.markdown, .plainText] }

    var text: String
    private var encoding = String.Encoding.utf8
    private var byteOrderMark = false

    init(text: String = "") {
        self.text = text
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        if let text = String(data: data, encoding: .utf8) {
            self.text = text
            byteOrderMark = data.starts(with: [0xEF, 0xBB, 0xBF])
        } else if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]), let text = String(data: data, encoding: .utf16) {
            self.text = text
            encoding = .utf16
        } else if let text = String(data: data, encoding: .windowsCP1252) {
            self.text = text
            encoding = .windowsCP1252
        } else {
            text = String(decoding: data.map { UInt16($0) }, as: UTF16.self)
            encoding = .isoLatin1
        }
    }

    func snapshot(contentType: UTType) throws -> String { text }

    func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
        var data = snapshot.data(using: encoding) ?? Data(snapshot.utf8)
        if byteOrderMark, encoding == .utf8 { data.insert(contentsOf: [0xEF, 0xBB, 0xBF], at: 0) }
        return FileWrapper(regularFileWithContents: data)
    }
}
