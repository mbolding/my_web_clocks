// Extraction — reads the text out of a file: PDFKit for PDFs, NSAttributedString for Word,
// RTF and OpenDocument, and the file itself for plain text. No other libraries.

import AppKit
import PDFKit
import UniformTypeIdentifiers

enum Extraction {
    static let docx = UTType(importedAs: "org.openxmlformats.wordprocessingml.document")
    static let doc = UTType(importedAs: "com.microsoft.word.doc")
    static let odt = UTType(importedAs: "org.oasis-open.opendocument.text")

    /// What the Open panel offers. Markdown and other text files conform to plain text.
    static let contentTypes: [UTType] = [.pdf, docx, doc, odt, .rtf, .rtfd, .plainText]

    enum Failure: LocalizedError {
        case unsupported(String)
        case unreadable
        case locked
        case noText(pdf: Bool)

        var errorDescription: String? {
            switch self {
            case .unsupported(let ext):
                "Text Extractor can't read \(ext.isEmpty ? "this kind of file" : ".\(ext) files"). It reads PDF, Word (.docx and .doc), RTF, OpenDocument and plain text files."
            case .unreadable:
                "This file couldn't be read. It may be damaged, or not what its name says it is."
            case .locked:
                "This PDF is protected by a password, so its text can't be read."
            case .noText(pdf: true):
                "This PDF has no text in it, only pictures of its pages. It's probably a scan."
            case .noText(pdf: false):
                "There's no text in this file."
            }
        }
    }

    /// The file's text as plain text with "\n" line endings. Slow for big files, so call it
    /// off the main thread.
    static func text(of url: URL) throws -> String {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: url.pathExtension)
        guard let type else { throw Failure.unsupported(url.pathExtension) }

        let raw: String
        if type.conforms(to: .pdf) {
            raw = try pdfText(url)
        } else if type.conforms(to: .plainText) {
            raw = try plainText(url)
        } else if let documentType = documentType(of: type) {
            guard let string = try? NSAttributedString(url: url, options: [.documentType: documentType],
                                                       documentAttributes: nil).string
            else { throw Failure.unreadable }
            raw = string
        } else {
            throw Failure.unsupported(url.pathExtension)
        }

        let text = tidy(raw)
        guard !text.isEmpty else { throw Failure.noText(pdf: type.conforms(to: .pdf)) }
        return text
    }

    private static func documentType(of type: UTType) -> NSAttributedString.DocumentType? {
        if type.conforms(to: docx) { return .officeOpenXML }
        if type.conforms(to: doc) { return .docFormat }
        if type.conforms(to: odt) { return .openDocument }
        if type.conforms(to: .rtfd) { return .rtfd }
        if type.conforms(to: .rtf) { return .rtf }
        return nil
    }

    /// Each page's text, with a blank line between pages.
    private static func pdfText(_ url: URL) throws -> String {
        guard let pdf = PDFDocument(url: url) else { throw Failure.unreadable }
        if pdf.isLocked { throw Failure.locked }
        return (0..<pdf.pageCount)
            .compactMap { pdf.page(at: $0)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private static func plainText(_ url: URL) throws -> String {
        guard let data = try? Data(contentsOf: url) else { throw Failure.unreadable }
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        var converted: NSString?
        NSString.stringEncoding(for: data, encodingOptions: nil, convertedString: &converted, usedLossyConversion: nil)
        guard let converted else { throw Failure.unreadable }
        return converted as String
    }

    /// Plain "\n" line endings, page breaks as new lines, and no placeholders for pictures.
    private static func tidy(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
            .replacingOccurrences(of: "\u{000C}", with: "\n")
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
