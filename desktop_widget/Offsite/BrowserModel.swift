// BrowserModel — one window's place in the account: the folder it shows, the history to go
// back and forward through, the snapshot it's looking into if any, and the transfers it has
// under way. Paths are relative to the account's home folder, which is "".

import AppKit
import UniformTypeIdentifiers

@MainActor
final class BrowserModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String, keyRefused: Bool)
    }

    struct Transfer: Identifiable {
        let id = UUID()
        var title: String
        var task: Task<Void, Never>?
    }

    @Published private(set) var folder = ""
    /// The ZFS snapshot being looked into, read-only, or nil for the account as it is now.
    @Published private(set) var snapshot: String?
    @Published private(set) var files: [RemoteFile] = []
    /// Dotfiles, which Finder hides too.
    @Published var showHidden = UserDefaults.standard.bool(forKey: "showHidden") {
        didSet {
            UserDefaults.standard.set(showHidden, forKey: "showHidden")
            if !showHidden { selection = selection.filter { !$0.hasPrefix(".") } }
        }
    }
    @Published private(set) var phase = Phase.loading
    @Published var selection = Set<String>()
    @Published var sortOrder = [KeyPathComparator(\RemoteFile.name, comparator: .localizedStandard)]
    @Published private(set) var snapshots: [String] = []
    @Published private(set) var transfers: [Transfer] = []
    @Published private(set) var usage: String?
    @Published var notice: String?
    /// What Quick Look shows; set once the file is fetched.
    @Published var preview: URL?

    private var back: [Place] = []
    private var forward: [Place] = []
    private var loadTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?

    private struct Place: Equatable {
        var folder: String
        var snapshot: String?
    }

    var readOnly: Bool { snapshot != nil }
    var canGoBack: Bool { !back.isEmpty }
    var canGoForward: Bool { !forward.isEmpty }
    var busy: Bool { !transfers.isEmpty }
    var shownFiles: [RemoteFile] { showHidden ? files : files.filter { !$0.name.hasPrefix(".") } }
    var selectedFiles: [RemoteFile] { shownFiles.filter { selection.contains($0.id) } }
    var sortedFiles: [RemoteFile] { shownFiles.sorted(using: sortOrder) }

    /// The folder's path on the account, looking into the snapshot if there is one.
    private var base: String {
        guard let snapshot else { return folder }
        return Remote.join(".zfs/snapshot/\(snapshot)", folder)
    }

    private var listPath: String { base.isEmpty ? "." : base }

    func path(of file: RemoteFile) -> String { Remote.join(base, file.name) }

    var title: String {
        let name = folder.isEmpty ? "Home" : folder.split(separator: "/").last.map(String.init) ?? folder
        return name
    }

    var subtitle: String {
        if let snapshot { return "As it was " + Self.label(snapshot) }
        return Remote.login
    }

    /// The folders from home down to this one, for the path bar.
    var crumbs: [(name: String, folder: String)] {
        var crumbs = [(name: "Home", folder: "")]
        var path = ""
        for part in folder.split(separator: "/") {
            path = Remote.join(path, String(part))
            crumbs.append((String(part), path))
        }
        return crumbs
    }

    // MARK: Going places

    func start() {
        reload()
        loadSnapshots()
        loadUsage()
    }

    func reload() {
        loadTask?.cancel()
        let path = listPath
        if files.isEmpty || phase != .ready { phase = .loading }
        loadTask = Task {
            do {
                let files = try await Remote.list(path)
                guard !Task.isCancelled else { return }
                self.files = files
                selection = selection.filter { name in files.contains { $0.id == name } }
                phase = .ready
            } catch is CancellationError {
            } catch let error as RemoteError {
                files = []
                phase = .failed(error.localizedDescription, keyRefused: error.keyRefused)
            } catch {
                files = []
                phase = .failed(error.localizedDescription, keyRefused: false)
            }
        }
    }

    func go(to folder: String, snapshot: String?? = .none) {
        let next = Place(folder: folder, snapshot: snapshot ?? self.snapshot)
        let here = Place(folder: self.folder, snapshot: self.snapshot)
        guard next != here else { return reload() }
        back.append(here)
        forward = []
        show(next)
    }

    func goBack() {
        guard let place = back.popLast() else { return }
        forward.append(Place(folder: folder, snapshot: snapshot))
        show(place)
    }

    func goForward() {
        guard let place = forward.popLast() else { return }
        back.append(Place(folder: folder, snapshot: snapshot))
        show(place)
    }

    func goUp() {
        guard !folder.isEmpty else { return }
        let parent = (folder as NSString).deletingLastPathComponent
        let child = (folder as NSString).lastPathComponent
        go(to: parent)
        selection = [child]
    }

    private func show(_ place: Place) {
        folder = place.folder
        snapshot = place.snapshot
        files = []
        selection = []
        reload()
    }

    /// Opens folders here and files with their app on the Mac.
    func open(_ ids: Set<String>) {
        let chosen = files.filter { ids.contains($0.id) }
        if chosen.count == 1, let file = chosen.first, file.isFolder || file.isLink {
            return go(to: Remote.join(folder, file.name))
        }
        for file in chosen where !file.isFolder {
            fetch(file) { NSWorkspace.shared.open($0) }
        }
    }

    func quickLook() {
        guard let file = selectedFiles.first(where: { !$0.isFolder }) else { return }
        fetch(file) { [weak self] in self?.preview = $0 }
    }

    // MARK: Snapshots and usage

    private func loadSnapshots() {
        Task {
            // Not every SSH account has ZFS snapshots; without them the menu stays hidden.
            let names = (try? await Remote.list(".zfs/snapshot"))?.map(\.name) ?? []
            snapshots = names.sorted { $0.localizedStandardCompare($1) == .orderedDescending }
        }
    }

    func loadUsage() {
        Task { usage = Usage.summary(try? await Remote.ssh("quota")) }
    }

    /// The same folder in a snapshot, or now with nil.
    func view(snapshot: String?) {
        go(to: folder, snapshot: .some(snapshot))
    }

    // MARK: Transfers

    func upload(_ urls: [URL]) {
        guard !readOnly else { return say("A snapshot can't be changed.") }
        let names = urls.map(\.lastPathComponent)
        let clashes = names.filter { name in files.contains { $0.name == name } }
        if !clashes.isEmpty {
            let alert = NSAlert()
            alert.messageText = clashes.count == 1 ? "Replace “\(clashes[0])”?" : "Replace \(clashes.count) items?"
            alert.informativeText = "This folder already has \(clashes.count == 1 ? "an item" : "items") with \(clashes.count == 1 ? "that name" : "those names"). A folder is merged with the one there, replacing files of the same name."
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let destination = listPath
        let commands = urls.map { "put -Rp \(Remote.quote($0.path)) \(Remote.quote(destination))" }
        transfer(urls.count == 1 ? "Uploading “\(names[0])”" : "Uploading \(urls.count) items") {
            try await Remote.sftp(commands)
        } then: { [weak self] in
            self?.selection = Set(names)
            self?.loadUsage()
        }
    }

    func chooseUploads() {
        guard !readOnly else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.prompt = "Upload"
        panel.message = "Choose files or folders to upload to \(title)"
        guard panel.runModal() == .OK else { return }
        upload(panel.urls)
    }

    /// Puts the selection in Downloads, under new names where those are taken, and shows it.
    func download() {
        let chosen = selectedFiles
        guard !chosen.isEmpty else { return }
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        var targets: [URL] = []
        let commands = chosen.map { file in
            let target = Self.unused(downloads.appendingPathComponent(file.name), besides: targets)
            targets.append(target)
            return "get -Rp \(Remote.quote(path(of: file))) \(Remote.quote(target.path))"
        }
        transfer(chosen.count == 1 ? "Downloading “\(chosen[0].name)”" : "Downloading \(chosen.count) items") {
            try await Remote.sftp(commands)
        } then: {
            NSWorkspace.shared.activateFileViewerSelecting(targets)
        }
    }

    /// A copy in the cache, fetched fresh each time, for opening or Quick Look.
    private func fetch(_ file: RemoteFile, then use: @escaping (URL) -> Void) {
        let folder = Remote.caches.appendingPathComponent("Open/\(UUID().uuidString)")
        let target = folder.appendingPathComponent(file.name)
        let source = path(of: file)
        transfer("Fetching “\(file.name)”") {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try await Remote.sftp(["get -p \(Remote.quote(source)) \(Remote.quote(target.path))"])
        } then: {
            use(target)
        }
    }

    func newFolder(named name: String) {
        guard let name = Self.validName(name), !readOnly else { return }
        let path = Remote.join(folder, name)
        transfer("Making “\(name)”") {
            try await Remote.sftp(["mkdir \(Remote.quote(path))"])
        } then: { [weak self] in
            self?.selection = [name]
        }
    }

    func rename(_ file: RemoteFile, to name: String) {
        guard let name = Self.validName(name), name != file.name, !readOnly else { return }
        if files.contains(where: { $0.name == name }) { return say("There's already an item called “\(name)”.") }
        let from = path(of: file), to = Remote.join(folder, name)
        transfer("Renaming “\(file.name)”") {
            try await Remote.sftp(["rename \(Remote.quote(from)) \(Remote.quote(to))"])
        } then: { [weak self] in
            self?.selection = [name]
        }
    }

    func delete() {
        let chosen = selectedFiles
        guard !chosen.isEmpty, !readOnly else { return }
        let alert = NSAlert()
        alert.messageText = chosen.count == 1 ? "Delete “\(chosen[0].name)”?" : "Delete \(chosen.count) items?"
        alert.informativeText = snapshots.isEmpty
            ? "This can't be undone."
            : "It's gone from the account now, but the snapshots taken while it was there still have it, until they expire."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let paths = chosen.map { (path(of: $0), $0.isFolder && !$0.isLink) }
        transfer(chosen.count == 1 ? "Deleting “\(chosen[0].name)”" : "Deleting \(chosen.count) items") {
            var commands: [String] = []
            for (path, isFolder) in paths { commands += try await Remote.deletion(of: path, isFolder: isFolder) }
            try await Remote.sftp(commands)
        } then: { [weak self] in
            self?.loadUsage()
        }
    }

    func copyPath() {
        let paths = selectedFiles.map { path(of: $0) }
        let text = paths.isEmpty ? (base.isEmpty ? "~" : base) : paths.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func cancel(_ transfer: Transfer) {
        transfer.task?.cancel()
    }

    /// Runs one piece of work in the status bar, then reloads the folder.
    private func transfer(_ title: String, _ work: @escaping () async throws -> Void,
                          then done: @escaping () -> Void = {}) {
        var transfer = Transfer(title: title)
        let id = transfer.id
        transfer.task = Task {
            do {
                try await work()
                done()
            } catch is CancellationError {
                say("Stopped.")
            } catch {
                say(error.localizedDescription)
            }
            transfers.removeAll { $0.id == id }
            reload()
        }
        transfers.append(transfer)
    }

    func say(_ message: String) {
        notice = message
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(message.count > 60 ? 8 : 4))
            if !Task.isCancelled { notice = nil }
        }
    }

    // MARK: Helpers

    /// rsync.net's snapshot names, like daily_2026-10-30, as the day ("Fri, Oct 30, 2026"),
    /// with the schedule in front unless it's the daily one. Other names stay as they are.
    static func label(_ snapshot: String) -> String {
        guard let match = snapshot.wholeMatch(of: #/(\w+?)_(\d{4}-\d{2}-\d{2})/#),
              let date = try? Date(String(match.2) + "T12:00:00Z", strategy: .iso8601) else { return snapshot }
        let day = date.formatted(.dateTime.weekday().month().day().year())
        return match.1 == "daily" ? day : "\(match.1.capitalized), \(day)"
    }

    private static func validName(_ name: String) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else { return nil }
        return name
    }

    /// The URL, or "name 2", "name 3"… where it's taken on disk or by an earlier target.
    private static func unused(_ url: URL, besides taken: [URL]) -> URL {
        func free(_ url: URL) -> Bool { !FileManager.default.fileExists(atPath: url.path) && !taken.contains(url) }
        guard !free(url) else { return url }
        let stem = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        let folder = url.deletingLastPathComponent()
        for n in 2... {
            let candidate = folder.appendingPathComponent(ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)")
            if free(candidate) { return candidate }
        }
        return url
    }
}

/// The account's quota command, boiled down to one line for the status bar. rsync.net's
/// prints a table of Usage, SoftQuota and Files, in gigabytes, under a header row; anything
/// else shows its last line as it is.
enum Usage {
    static func summary(_ output: String?) -> String? {
        guard let output else { return nil }
        let rows = output.split(separator: "\n").map { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
            .filter { !$0.isEmpty }
        if let header = rows.firstIndex(where: { $0.contains("Usage") && $0.contains("SoftQuota") }),
           header + 1 < rows.count {
            let names = rows[header], values = rows[header + 1]
            func value(_ name: String) -> Double? {
                names.firstIndex(of: name).flatMap { $0 < values.count ? Double(values[$0]) : nil }
            }
            if let used = value("Usage"), let quota = value("SoftQuota"), quota > 0 {
                var text = "\(gigabytes(used)) of \(gigabytes(quota)) used"
                if let files = value("Files") { text += ", \(Int(files).formatted()) files" }
                return text
            }
        }
        return rows.last?.joined(separator: " ")
    }

    private static func gigabytes(_ value: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value * 1_000_000_000), countStyle: .decimal)
    }
}

extension RemoteFile {
    @MainActor private static var icons: [String: NSImage] = [:]

    var kind: String {
        if isFolder { return "Folder" }
        if isLink { return "Alias" }
        let ext = (name as NSString).pathExtension
        // Some types' descriptions start in lower case, like "text".
        guard let description = UTType(filenameExtension: ext)?.localizedDescription, let first = description.first else {
            return ext.isEmpty ? "Document" : ext.uppercased() + " file"
        }
        return first.uppercased() + description.dropFirst()
    }

    @MainActor
    var icon: NSImage {
        let key = isFolder ? "/" : (name as NSString).pathExtension.lowercased()
        if let icon = Self.icons[key] { return icon }
        let type = isFolder ? UTType.folder : UTType(filenameExtension: key) ?? .data
        let icon = NSWorkspace.shared.icon(for: type)
        Self.icons[key] = icon
        return icon
    }
}
