// Offsite — a Finder-like window on an rsync.net account, or any other SSH account with
// sftp: browse its folders, drop files on the window to upload them, download, rename and
// delete, and look into the ZFS snapshots rsync.net keeps to get back what was there on an
// earlier day. It logs in with the Mac's own ssh and key, never a password. An ordinary Mac
// app like Map Browser, with windows, a menu bar and a Dock icon.

import SwiftUI
import AppKit

@main
struct OffsiteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            BrowserWindow()
        }
        .defaultSize(width: 820, height: 560)
        .commands {
            TextEditingCommands()
            OffsiteCommands()
        }

        Settings {
            OffsiteSettings()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Clears the copies fetched for opening and Quick Look, which have been handed to
    /// their apps by now.
    func applicationWillTerminate(_ notification: Notification) {
        try? FileManager.default.removeItem(at: Remote.caches.appendingPathComponent("Open"))
    }
}

struct OffsiteCommands: Commands {
    @FocusedObject private var model: BrowserModel?

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Folder…") { post(.offsiteNewFolder) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(model?.readOnly ?? true)
            Divider()
            Button("Upload…") { model?.chooseUploads() }
                .keyboardShortcut("u", modifiers: .command)
                .disabled(model?.readOnly ?? true)
            Button("Download") { model?.download() }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(model?.selection.isEmpty ?? true)
            Button("Quick Look") { model?.quickLook() }
                .keyboardShortcut("y", modifiers: .command)
                .disabled(model?.selection.isEmpty ?? true)
            Divider()
            Button("Rename…") { post(.offsiteRename) }
                .disabled(model?.readOnly ?? true || model?.selection.count != 1)
            Button("Delete…") { model?.delete() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(model?.readOnly ?? true || model?.selection.isEmpty ?? true)
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copy Path") { model?.copyPath() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(model == nil)
        }

        CommandGroup(after: .toolbar) {
            Button("Refresh") { model?.reload() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model == nil)
            Button(model?.showHidden ?? false ? "Hide Hidden Files" : "Show Hidden Files") { model?.showHidden.toggle() }
                .keyboardShortcut(".", modifiers: [.command, .shift])
                .disabled(model == nil)
            Divider()
        }

        CommandMenu("Go") {
            Button("Back") { model?.goBack() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!(model?.canGoBack ?? false))
            Button("Forward") { model?.goForward() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!(model?.canGoForward ?? false))
            Button("Enclosing Folder") { model?.goUp() }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(model?.folder.isEmpty ?? true)
            Button("Open") { if let model { model.open(model.selection) } }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(model?.selection.isEmpty ?? true)
            Divider()
            Button("Home") { model?.go(to: "") }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(model == nil)
            if let model, !model.snapshots.isEmpty {
                Menu("Snapshots") {
                    Button("Now") { model.view(snapshot: nil) }
                    Divider()
                    ForEach(model.snapshots, id: \.self) { name in
                        Button(BrowserModel.label(name)) { model.view(snapshot: name) }
                    }
                }
            }
        }
    }

    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: model)
    }
}

struct OffsiteSettings: View {
    @AppStorage("login") private var login = ""

    var body: some View {
        Form {
            TextField("Account:", text: $login, prompt: Text("user@host"))
            Text("Your login, as user@host, or a Host from ~/.ssh/config. It logs in with this Mac's SSH key, so there's no password to keep.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 440)
    }
}
