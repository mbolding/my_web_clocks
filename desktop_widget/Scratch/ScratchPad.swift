// ScratchPad — the scratch pad's text, kept as you type, and what you can do with it:
// copy it all to the clipboard, or save it as a new Markdown file on the Desktop, named
// after its first line (or the date and time, if that's empty), with a number added
// rather than overwrite a file of the same name.

import AppKit

@MainActor
final class ScratchPad: ObservableObject {
    static let shared = ScratchPad()

    @Published var text = UserDefaults.standard.string(forKey: "text") ?? "" {
        didSet { UserDefaults.standard.set(text, forKey: "text") }
    }
    /// A brief note after copying or saving, shown in place of the word count.
    @Published private(set) var notice: String?
    @Published private(set) var lastSaved: URL?

    private var noticeTimer: Timer?
    private var keyMonitor: Any?

    private init() {
        installKeys()
    }

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func copyAll() {
        guard !isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        show("Copied")
    }

    func saveToDesktop() {
        guard !isEmpty else { return }
        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let name = Self.fileName(for: text)
        var url = desktop.appendingPathComponent("\(name).md")
        var n = 1
        while FileManager.default.fileExists(atPath: url.path) {
            n += 1
            url = desktop.appendingPathComponent("\(name)_\(n).md")
        }
        do {
            try (text.hasSuffix("\n") ? text : text + "\n").write(to: url, atomically: true, encoding: .utf8)
            lastSaved = url
            show("Saved \(url.lastPathComponent)")
        } catch {
            show("Couldn't save: \(error.localizedDescription)")
        }
    }

    /// The first line's words joined by underscores, with only letters, digits and
    /// underscores kept and cut to a few words, or "Scratch" and the date and time if that
    /// leaves nothing. Spaces, dashes and other punctuation go, since they can mean
    /// something to the shell (a leading dash reads as an option); underscores are safe.
    static func fileName(for text: String, at date: Date = .now) -> String {
        let firstLine = text.prefix(while: { !$0.isNewline }).filter { $0 != "'" && $0 != "’" } // don't → dont
        let kept = String(firstLine.map { $0.isLetter || $0.isNumber || $0 == "_" ? $0 : " " })
        var name = ""
        for word in kept.split(separator: " ") {
            guard name.count + word.count < 60 else { break }
            name += (name.isEmpty ? "" : "_") + word
        }
        if name.isEmpty, let word = kept.split(separator: " ").first {
            name = String(word.prefix(60)) // one very long word
        }
        if !name.isEmpty { return name }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyyMMdd_HHmmss" // no punctuation, as above, so it still sorts by date
        return "Scratch_\(format.string(from: date))"
    }

    func revealLastSaved() {
        if let lastSaved { NSWorkspace.shared.activateFileViewerSelecting([lastSaved]) }
    }

    func clear() {
        text = ""
    }

    private func show(_ message: String) {
        notice = message
        noticeTimer?.invalidate()
        noticeTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.notice = nil }
        }
    }

    // MARK: - Keys

    /// There's no menu bar in this app, so the usual edit shortcuts have nothing to route
    /// through; handle them before the text view sees them. ⌘S saves to the Desktop.
    private func installKeys() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window?.isKeyWindow == true else { return event }
            return MainActor.assumeIsolated { self.handle(event) } ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if mods == [.command, .shift], key == "z" { return NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }
        guard mods == .command else { return false }
        let actions: [String: Selector] = ["x": #selector(NSText.cut(_:)), "c": #selector(NSText.copy(_:)),
                                           "v": #selector(NSText.paste(_:)), "a": #selector(NSText.selectAll(_:)),
                                           "z": Selector(("undo:"))]
        if let action = actions[key] { return NSApp.sendAction(action, to: nil, from: nil) }
        if key == "s" { saveToDesktop(); return true }
        return false
    }
}
