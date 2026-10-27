// CommandSession — one long-lived zsh that runs typed commands in turn, so cd, variables
// and aliases carry over. It starts as a login shell (your PATH from .zprofile) and then
// quietly sources .zshrc for aliases. Each command runs with stdin from /dev/null, so
// nothing can sit waiting for input, and is followed by a marker line carrying its exit
// status and the shell's folder afterwards. Also holds the input line, its history, and
// file name completion.

import AppKit

struct Block: Identifiable {
    let id = UUID()
    var command: String
    var output = ""
    var lines = 0
    var status: Int32? // nil while running
}

@MainActor
final class CommandSession: ObservableObject {
    static let shared = CommandSession()

    @Published private(set) var blocks: [Block] = []
    @Published private(set) var folder: URL
    @Published private(set) var branch: String? // nil outside a git repository
    @Published private(set) var hasChanges = false
    @Published private(set) var isRunning = false
    @Published var line = ""
    @Published var hint = ""
    @Published private(set) var focusRequests = 0 // bumped when a folder arrives, to focus the input

    private var process: Process?
    private var queuedFolder: URL? // arrived while a command was running
    private var commandNames: Set<String> = [] // for Tab on a command name, refreshed after each command
    private var collectedNames: Set<String>? // being read from the shell
    private var input: FileHandle?
    private let token = "__commandbar_\(UUID().uuidString)__"
    private var pending = Data()
    private var hidden = false // the running command is setup, not something you typed
    private var interrupts = 0
    private var ready = false // this shell got through its setup
    private var history: [String]
    private var historyIndex: Int?
    private var keyMonitor: Any?

    private static let maxBlocks = 200, maxLines = 2000
    private static let escapes = try! NSRegularExpression(pattern: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]|.\u{08}")

    private init() {
        let saved = UserDefaults.standard.string(forKey: "folder").map { URL(fileURLWithPath: $0) }
        folder = saved.flatMap { Self.isDirectory($0) ? $0 : nil } ?? FileManager.default.homeDirectoryForCurrentUser
        history = UserDefaults.standard.stringArray(forKey: "history") ?? []
        start()
        installKeys()
    }

    // MARK: - Shell

    private func start() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-l"]
        p.currentDirectoryURL = folder
        var env = ProcessInfo.processInfo.environment
        // No terminal here, so keep tools from paging or colouring their output.
        env.merge(["TERM": "dumb", "PAGER": "cat", "GIT_PAGER": "cat", "MANPAGER": "cat", "NO_COLOR": "1"]) { $1 }
        p.environment = env

        let stdin = Pipe(), stdout = Pipe()
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = stdout
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.receive(data) } }
        }
        p.terminationHandler = { [weak self] p in
            let status = p.terminationStatus
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.shellExited(status) } }
        }

        do {
            try p.run()
        } catch {
            blocks.append(Block(command: "zsh", output: "Couldn't start /bin/zsh: \(error.localizedDescription)\n", status: -1))
            return
        }
        process = p
        input = stdin.fileHandleForWriting
        ready = false
        send("[[ -f ~/.zshrc ]] && source ~/.zshrc >/dev/null 2>&1", hidden: true)
    }

    private func send(_ command: String, hidden: Bool = false) {
        guard let input else { return }
        isRunning = true
        interrupts = 0
        self.hidden = hidden
        if !hidden {
            blocks.append(Block(command: command))
            if blocks.count > Self.maxBlocks { blocks.removeFirst(blocks.count - Self.maxBlocks) }
        }
        // base64 keeps the command's quotes and newlines away from the shell's own parsing;
        // eval then runs it in this shell, so cd and friends stick. Afterwards the shell
        // lists every command name it knows (PATH, aliases, functions, builtins; rehash
        // picks up anything just installed) for Tab, then the marker line, which also
        // carries the git branch (short hash when detached, - outside a repo) and whether
        // there are uncommitted changes; branch names can't contain spaces.
        let encoded = Data(command.utf8).base64EncodedString()
        let script = """
            __commandbar=$(print -r -- \(encoded) | base64 --decode)
            { eval "$__commandbar" } < /dev/null
            __commandbar_status=$?
            rehash 2>/dev/null
            print -r -- \(token):names
            print -rl -- ${(k)commands} ${(k)aliases} ${(k)functions} ${(k)builtins} ${(k)reswords}
            __commandbar_branch=$(git symbolic-ref --short -q HEAD 2>/dev/null </dev/null || git rev-parse --short HEAD 2>/dev/null </dev/null)
            __commandbar_dirty=0
            [[ -n $__commandbar_branch && -n $(git status --porcelain 2>/dev/null </dev/null | head -1) ]] && __commandbar_dirty=1
            printf '%s %d %s %d %s\\n' \(token) $__commandbar_status "${__commandbar_branch:--}" $__commandbar_dirty "$PWD"

            """
        input.write(Data(script.utf8))
    }

    private func receive(_ data: Data) {
        pending.append(data)
        var current = blocks
        while let newline = pending.firstIndex(of: 0x0A) {
            let text = String(decoding: pending[pending.startIndex..<newline], as: UTF8.self)
            pending.removeSubrange(...newline)

            // Output without a trailing newline runs straight into the names line.
            if let names = text.range(of: token + ":names") {
                if names.lowerBound > text.startIndex { append(String(text[..<names.lowerBound]), to: &current) }
                collectedNames = []
                continue
            }
            guard let marker = text.range(of: token) else {
                if collectedNames != nil {
                    collectedNames!.insert(text)
                } else {
                    append(text, to: &current)
                }
                continue
            }
            if marker.lowerBound > text.startIndex { append(String(text[..<marker.lowerBound]), to: &current) }
            if let collected = collectedNames {
                commandNames = collected
                collectedNames = nil
            }
            // status, branch, dirty flag, folder
            let fields = text[marker.upperBound...].split(separator: " ", maxSplits: 3)
            if !hidden, !current.isEmpty, let status = fields.first.flatMap({ Int32($0) }) {
                current[current.count - 1].status = status
            }
            if fields.count == 4 {
                branch = fields[1] == "-" ? nil : String(fields[1])
                hasChanges = fields[2] == "1"
                folder = URL(fileURLWithPath: String(fields[3]))
                UserDefaults.standard.set(folder.path, forKey: "folder")
            }
            hidden = false
            isRunning = false
            ready = true
        }
        blocks = current
        // Only now, since send adds a block and the loop above worked on a copy.
        if !isRunning, let dir = queuedFolder {
            queuedFolder = nil
            send(Self.cd(dir))
        }
    }

    private func append(_ text: String, to blocks: inout [Block]) {
        guard !hidden, !blocks.isEmpty else { return }
        let clean = Self.escapes.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                                          withTemplate: "")
        let i = blocks.count - 1
        blocks[i].output += clean + "\n"
        blocks[i].lines += 1
        // Keep long output to its last few thousand lines.
        if blocks[i].lines > Self.maxLines + 500 {
            let drop = blocks[i].output.split(separator: "\n", maxSplits: 500, omittingEmptySubsequences: false)
            blocks[i].output = "…\n" + (drop.last.map(String.init) ?? "")
            blocks[i].lines -= 499
        }
    }

    private func shellExited(_ status: Int32) {
        process = nil
        input = nil
        pending = Data()
        collectedNames = nil
        if isRunning, !hidden, !blocks.isEmpty {
            blocks[blocks.count - 1].status = status
            blocks[blocks.count - 1].output += "(shell exited; started a new one)\n"
        }
        isRunning = false
        // A shell that died before finishing its setup would only die again.
        if ready {
            start()
        } else {
            blocks.append(Block(command: "zsh", output: "zsh exited (status \(status)) while starting up.\n", status: status))
        }
    }

    // MARK: - Commands

    func submit() {
        let command = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        guard !isRunning, input != nil else { NSSound.beep(); return }
        if history.last != command {
            history.append(command)
            history = Array(history.suffix(500))
            UserDefaults.standard.set(history, forKey: "history")
        }
        historyIndex = nil
        line = ""
        hint = ""
        send(command)
    }

    /// cd to a folder, or to the folder holding a file: dropped on the window, opened
    /// with the app, or sent from Finder. If a command is running, go there once it ends.
    func go(to url: URL) {
        guard input != nil else { NSSound.beep(); return }
        let dir = Self.isDirectory(url) ? url : url.deletingLastPathComponent()
        focusRequests += 1
        if isRunning {
            queuedFolder = dir
            if !hidden { hint = "cd to \(dir.lastPathComponent) when this finishes" }
        } else {
            send(Self.cd(dir))
        }
    }

    private static func cd(_ dir: URL) -> String {
        "cd -- '\(dir.path.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    /// ⌃C: interrupt whatever the shell started. If that doesn't stop it (a loop in the
    /// shell itself), a second ⌃C replaces the shell with a fresh one in the same folder.
    func interrupt() {
        guard isRunning, let process else { return }
        interrupts += 1
        if interrupts == 1 {
            let pkill = Process()
            pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            pkill.arguments = ["-INT", "-P", String(process.processIdentifier)]
            try? pkill.run()
        } else {
            ready = true // so shellExited starts a new one, even mid-setup
            process.terminate()
        }
    }

    func clear() {
        blocks = isRunning && !hidden ? Array(blocks.suffix(1)) : []
    }

    func revealFolder() {
        NSWorkspace.shared.open(folder)
    }

    // MARK: - History and completion

    func historyStep(_ step: Int) {
        guard !history.isEmpty else { return }
        let i = (historyIndex ?? history.count) + step
        if i >= history.count {
            historyIndex = nil
            line = ""
        } else {
            historyIndex = max(i, 0)
            line = history[historyIndex!]
        }
    }

    /// Completes the last word of the line, like zsh's Tab: a command name where a command
    /// goes (start of the line, after | ; & ( or sudo and the like), otherwise a file name.
    /// Several matches extend to what they share and list the rest in the hint line.
    func complete() {
        var start = line.endIndex
        while start > line.startIndex {
            let prev = line.index(before: start)
            if line[prev] == " ", prev == line.startIndex || line[line.index(before: prev)] != "\\" { break }
            start = prev
        }
        // A command can start inside the word too, as in x=$(pbp or ls;pbp; keep what's
        // before it as typed.
        var raw = String(line[start...]), lead = ""
        if let sep = raw.lastIndex(where: { "|;&(`".contains($0) }) {
            lead = String(raw[...sep])
            raw = String(raw[raw.index(after: sep)...])
        }
        let word = raw.replacingOccurrences(of: "\\ ", with: " ")
        let slash = word.lastIndex(of: "/")
        let dirPart = slash.map { String(word[...$0]) } ?? ""
        let namePart = slash.map { String(word[word.index(after: $0)...]) } ?? word

        var matches: [String] = []
        var isDirectory: (String) -> Bool = { _ in false }
        if dirPart.isEmpty, !word.hasPrefix("~"), !lead.isEmpty || Self.isCommandPosition(line[..<start]) {
            // Leading-underscore names are completion internals unless asked for.
            matches = commandNames.filter { $0.hasPrefix(word) && (word.hasPrefix("_") || !$0.hasPrefix("_")) }.sorted()
        }
        if matches.isEmpty {
            let expanded = (dirPart as NSString).expandingTildeInPath
            let base = dirPart.isEmpty ? folder
                : expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : folder.appendingPathComponent(expanded)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? []
            matches = names
                .filter { (namePart.hasPrefix(".") || !$0.hasPrefix(".")) && $0.lowercased().hasPrefix(namePart.lowercased()) }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            isDirectory = { Self.isDirectory(base.appendingPathComponent($0)) }
        }
        guard let first = matches.first else { NSSound.beep(); return }

        var name: String, suffix = ""
        if matches.count == 1 {
            name = first
            suffix = isDirectory(first) ? "/" : " "
        } else {
            let lowered = matches.map { Array($0.lowercased()) }
            var shared = lowered[0].count
            for other in lowered.dropFirst() {
                shared = min(shared, zip(lowered[0], other).prefix { $0 == $1 }.count)
            }
            name = shared > namePart.count ? String(first.prefix(shared)) : namePart
            let listed = matches.prefix(60).map { isDirectory($0) ? $0 + "/" : $0 }
            hint = listed.joined(separator: "  ") + (matches.count > 60 ? "  …" : "")
        }
        line = String(line[..<start]) + lead + (dirPart + name).replacingOccurrences(of: " ", with: "\\ ") + suffix
    }

    private static let commandPrefixes: Set = ["sudo", "time", "nohup", "xargs", "exec", "command", "builtin",
                                               "which", "type", "whence", "where", "man", "env", "watch"]

    /// Whether a command name goes after `before`: nothing, a separator, or a word like sudo.
    private static func isCommandPosition(_ before: Substring) -> Bool {
        let trimmed = before.trimmingCharacters(in: .whitespaces)
        guard let last = trimmed.last else { return true }
        return "|;&({`".contains(last) || commandPrefixes.contains(String(trimmed.split(separator: " ").last ?? ""))
    }

    // MARK: - Keys

    /// There's no menu bar in this app, so the usual edit shortcuts have nothing to route
    /// through; handle them, along with the shell keys, before the text field sees them.
    private func installKeys() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window?.isKeyWindow == true else { return event }
            return MainActor.assumeIsolated { self.handle(event) } ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers ?? ""

        if mods == .control, key == "c" { interrupt(); return true }
        if mods == .command {
            let actions: [String: Selector] = ["x": #selector(NSText.cut(_:)), "c": #selector(NSText.copy(_:)),
                                               "v": #selector(NSText.paste(_:)), "a": #selector(NSText.selectAll(_:)),
                                               "z": Selector(("undo:"))]
            if let action = actions[key] { return NSApp.sendAction(action, to: nil, from: nil) }
            if key == "k" { clear(); return true }
            return false
        }
        guard mods.subtracting([.numericPad, .function]).isEmpty else { return false }
        switch event.keyCode {
        case 126: historyStep(-1); return true // up
        case 125: historyStep(1); return true // down
        case 48: complete(); return true // tab
        default: hint = ""; return false
        }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}
