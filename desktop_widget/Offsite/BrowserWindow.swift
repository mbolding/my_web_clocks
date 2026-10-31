// BrowserWindow — one window on the account, laid out like a Finder list: the folder's
// files in a table, the path from home along the foot, and the transfers under way beside
// it. Drop files from Finder on the window to upload them; double-click to open, Space for
// Quick Look. The Snapshots menu shows the same folder as it was on an earlier day.

import SwiftUI
import AppKit
import QuickLook

struct BrowserWindow: View {
    @StateObject private var model = BrowserModel()
    @AppStorage("login") private var login = ""
    @AppStorage("accent", store: Accent.defaults) private var accent = Accent.orange
    @State private var targeted = false
    @State private var naming: Naming?
    @State private var name = ""

    /// The name being asked for, for a new folder or a rename.
    enum Naming: Identifiable {
        case newFolder
        case rename(RemoteFile)
        var id: String { if case .rename(let file) = self { "rename " + file.name } else { "new" } }
    }

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            statusBar
        }
        .frame(minWidth: 520, minHeight: 320)
        .overlay {
            if targeted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(accent.color, lineWidth: 3)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            if let notice = model.notice {
                Text(notice)
                    .font(.callout)
                    .foregroundStyle(accent.color)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
                    .padding(.bottom, 40)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.notice)
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty, !model.readOnly, model.phase == .ready else { return false }
            model.upload(files)
            return true
        } isTargeted: { targeted = $0 && !model.readOnly }
        .toolbar { toolbar }
        .navigationTitle(model.title)
        .navigationSubtitle(model.subtitle)
        .quickLookPreview($model.preview)
        .focusedSceneObject(model)
        .task(id: login) { model.start() }
        .sheet(item: $naming) { naming in
            NameSheet(title: naming.title, button: naming.button, name: $name) {
                switch naming {
                case .newFolder: model.newFolder(named: name)
                case .rename(let file): model.rename(file, to: name)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .offsiteNewFolder)) { note in
            if note.object as? BrowserModel === model { askForNewFolder() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .offsiteRename)) { note in
            if note.object as? BrowserModel === model { askToRename() }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .failed(let message, let keyRefused):
            Failure(message: message, keyRefused: keyRefused, login: login) { model.start() }
        case .loading where model.files.isEmpty:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            table
        }
    }

    private var table: some View {
        Table(model.sortedFiles, selection: $model.selection, sortOrder: $model.sortOrder) {
            TableColumn("Name", value: \.name, comparator: .localizedStandard) { file in
                HStack(spacing: 6) {
                    Image(nsImage: file.icon).resizable().frame(width: 16, height: 16)
                    Text(file.name).lineLimit(1).truncationMode(.middle)
                    if file.isLink {
                        Image(systemName: "arrow.turn.up.right").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .width(min: 180, ideal: 320)
            TableColumn("Date Modified", value: \.sortDate) { file in
                Text(file.modified.map { $0.formatted(date: .abbreviated, time: file.hasTime ? .shortened : .omitted) } ?? "--").foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 160)
            TableColumn("Size", value: \.sortSize) { file in
                Text(file.isFolder ? "--" : ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 80)
            TableColumn("Kind", value: \.kind) { file in
                Text(file.kind).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 70, ideal: 130)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            menu(for: ids)
        } primaryAction: { ids in
            model.open(ids)
        }
        .onKeyPress(.space) {
            model.quickLook()
            return .handled
        }
        .onKeyPress(.return) {
            model.open(model.selection)
            return .handled
        }
        .overlay {
            if model.shownFiles.isEmpty, model.phase == .ready {
                Text(model.readOnly ? "Empty in this snapshot" : "Empty. Drop files here to upload them.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func menu(for ids: Set<String>) -> some View {
        if ids.isEmpty {
            Button("New Folder…") { askForNewFolder() }.disabled(model.readOnly)
            Button("Copy Path") { model.copyPath() }
        } else {
            Button("Open") { model.open(ids) }
            Button("Quick Look") { model.quickLook() }
            Button("Download") { model.download() }
            Divider()
            Button("Rename…") { askToRename() }.disabled(model.readOnly || ids.count != 1)
            Button("Copy Path") { model.copyPath() }
            Divider()
            Button("Delete…") { model.delete() }.disabled(model.readOnly)
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { model.goBack() } label: { Label("Back", systemImage: "chevron.left") }
                .help("Back (⌘[)")
                .disabled(!model.canGoBack)
            Button { model.goForward() } label: { Label("Forward", systemImage: "chevron.right") }
                .help("Forward (⌘])")
                .disabled(!model.canGoForward)
        }
        ToolbarItemGroup {
            if !model.snapshots.isEmpty {
                Menu {
                    Button("Now") { model.view(snapshot: nil) }
                    Divider()
                    ForEach(model.snapshots, id: \.self) { name in
                        Button(BrowserModel.label(name)) { model.view(snapshot: name) }
                    }
                } label: {
                    Label(model.snapshot.map(BrowserModel.label) ?? "Now", systemImage: model.readOnly ? "clock.arrow.circlepath" : "clock")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(model.readOnly ? accent.color : .primary)
                }
                .help("See this folder as it was in one of the account's snapshots")
            }
            Button { askForNewFolder() } label: { Label("New Folder", systemImage: "folder.badge.plus") }
                .help("New folder (⇧⌘N)")
                .disabled(model.readOnly || model.phase != .ready)
            Button { model.chooseUploads() } label: { Label("Upload", systemImage: "square.and.arrow.up") }
                .help("Upload files from the Mac (⌘U), or drop them on the window")
                .disabled(model.readOnly || model.phase != .ready)
            Button { model.download() } label: { Label("Download", systemImage: "square.and.arrow.down") }
                .help("Download the selection to Downloads (⌘D)")
                .disabled(model.selection.isEmpty)
            Button { model.delete() } label: { Label("Delete", systemImage: "trash") }
                .help("Delete the selection (⌘⌫)")
                .disabled(model.readOnly || model.selection.isEmpty)
            Button { model.reload() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .help("Refresh (⌘R)")
        }
    }

    /// The path from home, each folder a button, and the work under way.
    private var statusBar: some View {
        HStack(spacing: 4) {
            ForEach(Array(model.crumbs.enumerated()), id: \.offset) { index, crumb in
                if index > 0 { Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.tertiary) }
                Button(crumb.name) { model.go(to: crumb.folder) }
                    .buttonStyle(.plain)
                    .foregroundStyle(index == model.crumbs.count - 1 ? .primary : .secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            if let transfer = model.transfers.first {
                ProgressView().controlSize(.mini)
                Text(transfer.title + (model.transfers.count > 1 ? " and \(model.transfers.count - 1) more" : "") + "…")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button { model.cancel(transfer) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Stop")
            } else if let usage = model.usage {
                Text(usage).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    func askForNewFolder() {
        guard !model.readOnly, model.phase == .ready else { return }
        name = "untitled folder"
        naming = .newFolder
    }

    func askToRename() {
        guard !model.readOnly, model.selectedFiles.count == 1, let file = model.selectedFiles.first else { return }
        name = file.name
        naming = .rename(file)
    }
}

extension BrowserWindow.Naming {
    var title: String { if case .rename(let file) = self { "Rename “\(file.name)”" } else { "New Folder" } }
    var button: String { if case .rename = self { "Rename" } else { "Make Folder" } }
}

extension Notification.Name {
    static let offsiteNewFolder = Notification.Name("offsiteNewFolder")
    static let offsiteRename = Notification.Name("offsiteRename")
}

private struct NameSheet: View {
    var title: String
    var button: String
    @Binding var name: String
    var done: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            TextField("Name", text: $name)
                .frame(width: 300)
                .onSubmit(submit)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(button, action: submit).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }

    private func submit() {
        dismiss()
        done()
    }
}

/// Why the folder couldn't be shown. A refused key is the usual first-time trouble, so that
/// one says how to add the key, which takes the account's password once in Terminal.
private struct Failure: View {
    var message: String
    var keyRefused: Bool
    var login: String
    var retry: () -> Void
    @State private var account = ""

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: login.isEmpty ? "externaldrive.badge.plus" : "exclamationmark.triangle")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            if login.isEmpty {
                Text("Which account?").font(.title3.bold())
                Text("Your login, as user@host, or a Host from ~/.ssh/config. It logs in with this Mac's SSH key, never a password.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 380)
                HStack {
                    TextField("user@host", text: $account)
                        .frame(width: 240)
                        .onSubmit(connect)
                    Button("Connect", action: connect).keyboardShortcut(.defaultAction)
                        .disabled(account.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else {
                Text(message).font(.title3.bold()).multilineTextAlignment(.center).textSelection(.enabled)
                if keyRefused {
                    Text("Add the key once from Terminal, typing the account's password when it asks:")
                        .foregroundStyle(.secondary)
                    let command = KeySetup.command(for: login)
                    Text(command)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        .frame(maxWidth: 520)
                    HStack {
                        Button("Copy Command") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(command, forType: .string)
                        }
                        Button("Try Again", action: retry).keyboardShortcut(.defaultAction)
                    }
                } else {
                    Button("Try Again", action: retry).keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func connect() {
        let account = account.trimmingCharacters(in: .whitespaces)
        guard !account.isEmpty else { return }
        UserDefaults.standard.set(account, forKey: "login")
    }
}

enum KeySetup {
    /// The public key ssh would offer first.
    static var publicKey: String {
        let ssh = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        for name in ["id_ed25519.pub", "id_ecdsa.pub", "id_rsa.pub"]
        where FileManager.default.fileExists(atPath: ssh.appendingPathComponent(name).path) {
            return "~/.ssh/" + name
        }
        return "~/.ssh/id_ed25519.pub"
    }

    /// rsync.net's own way to add a key, which keeps any already there; ssh-copy-id elsewhere.
    static func command(for login: String) -> String {
        if login.lowercased().hasSuffix("rsync.net") {
            return "cat \(publicKey) | ssh \(login) 'dd of=.ssh/authorized_keys oflag=append conv=notrunc'"
        }
        return "ssh-copy-id -i \(publicKey) \(login)"
    }
}
