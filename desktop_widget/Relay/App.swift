// Relay Chat — an IRC client, for the chat networks that have run since 1988 and still do:
// SDF's own, the tildeverse's tilde.chat, and Libera.Chat, where most open-source projects
// talk. An ordinary Mac app with one window, but closing it doesn't leave the channels: the
// app stays connected with its Dock icon, counts mentions and private messages on it, and
// sends a notification for them. Quitting says goodbye to each network, and the networks that
// were connected come back at the next launch.

import SwiftUI
import AppKit
import UserNotifications

@main
struct RelayChatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Relay Chat", id: "main") {
            ChatWindow()
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            SidebarCommands()
            TextEditingCommands()
            ChatCommands()
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        MainActor.assumeIsolated { Chat.shared.start() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Clicking the Dock icon with the window closed brings it back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { MainActor.assumeIsolated { Chat.shared.openWindow?(id: "main") } }
        return true
    }

    /// Sends QUIT to each network, and gives the lines a moment to leave before quitting.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let waiting = MainActor.assumeIsolated { Chat.shared.quitAll() }
        guard waiting else { return .terminateNow }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        MainActor.assumeIsolated { Chat.shared.appBecameActive() }
    }

    // Notifications show even while the app is in front, as long as the conversation isn't.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let network = info["network"] as? String, let buffer = info["buffer"] as? String {
            DispatchQueue.main.async { MainActor.assumeIsolated { Chat.shared.show(network: network, buffer: buffer) } }
        }
        completionHandler()
    }
}

struct ChatCommands: Commands {
    @ObservedObject private var chat = Chat.shared
    @AppStorage("fontSize") private var fontSize = 13.0
    @AppStorage("showEvents") private var showEvents = true
    @Environment(\.openWindow) private var openWindow

    private var session: Session? { chat.selection.flatMap { chat.session($0.network) } }

    var body: some Commands {
        let _ = chat.openWindow = openWindow

        CommandGroup(after: .newItem) {
            Button("Join Channel…") { chat.joining = session }
                .keyboardShortcut("j", modifiers: .command)
                .disabled(session?.state != .connected)
            Button("Leave Channel") {
                if let ref = chat.selection, let session { session.close(ref) }
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
            .disabled(chat.selection?.name.isEmpty ?? true)
        }

        CommandMenu("Network") {
            ForEach(chat.sessions) { session in
                NetworkMenu(session: session)
            }
        }

        CommandGroup(before: .toolbar) {
            Toggle("Show Joins and Departures", isOn: $showEvents)
            Toggle("Show People", isOn: $chat.showUsers)
                .keyboardShortcut("u", modifiers: [.command, .option])
            Divider()
            Button("Bigger Text") { fontSize = min(fontSize + 1, 32) }
                .keyboardShortcut("=", modifiers: .command)
            Button("Smaller Text") { fontSize = max(fontSize - 1, 9) }
                .keyboardShortcut("-", modifiers: .command)
            Button("Actual Size") { fontSize = 13 }
                .keyboardShortcut("0", modifiers: .command)
            Divider()
        }

        CommandGroup(replacing: .help) {
            Link("SDF's IRC Network", destination: URL(string: "https://sdf.org/?tutorials/irc")!)
            Link("tilde.chat", destination: URL(string: "https://tilde.chat")!)
            Link("Libera.Chat Guides", destination: URL(string: "https://libera.chat/guides/")!)
        }
    }
}

/// Connect and Disconnect for one network, in the Network menu.
struct NetworkMenu: View {
    @ObservedObject var session: Session

    var body: some View {
        if session.state == .disconnected {
            Button("Connect to \(session.network.name)") { Chat.shared.connect(session) }
        } else {
            Button("Disconnect from \(session.network.name)") { session.disconnect() }
        }
        Button("Log In or Register on \(session.network.name)…") { Chat.shared.accountFor = session }
            .disabled(session.state != .connected)
        Divider()
    }
}
