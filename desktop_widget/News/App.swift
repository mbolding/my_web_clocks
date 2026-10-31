// News Reader — a Usenet newsreader, for the discussion groups that have run over NNTP since
// 1986 and still do: the tildeverse's own groups, mailing lists through Gmane, and the whole
// of Usenet through a free Eternal September account. An ordinary Mac app like Gopher
// Browser, with windows, a menu bar, a Dock icon and a Settings window for servers and for
// the name posts go out under.

import SwiftUI
import AppKit

@main
struct NewsReaderApp: App {
    var body: some Scene {
        WindowGroup {
            ReaderWindow()
        }
        .defaultSize(width: 1240, height: 780)
        .commands {
            SidebarCommands()
            TextEditingCommands()
            NewsCommands()
        }

        Settings {
            SettingsView()
        }
    }
}

struct NewsCommands: Commands {
    @FocusedObject private var model: ReaderModel?
    @AppStorage("fontSize") private var fontSize = 13.0

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Post") { model?.newPost() }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(model?.group == nil)
            Button("Follow Up") { model?.followUp() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model?.article == nil)
        }

        CommandGroup(before: .toolbar) {
            Toggle("Show All Headers", isOn: Binding(get: { model?.showAllHeaders ?? false },
                                                     set: { model?.showAllHeaders = $0 }))
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(model?.article == nil)
            Divider()
            Button("Bigger Text") { fontSize = min(fontSize + 1, 32) }
                .keyboardShortcut("=", modifiers: .command)
            Button("Smaller Text") { fontSize = max(fontSize - 1, 9) }
                .keyboardShortcut("-", modifiers: .command)
            Button("Actual Size") { fontSize = 13 }
                .keyboardShortcut("0", modifiers: .command)
            Divider()
        }

        CommandMenu("Articles") {
            Button("Get New Articles") { model?.refresh() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(model?.group == nil)
            Button("Next Unread Article") { model?.nextUnread() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(model?.rows.isEmpty ?? true)
            Divider()
            Button("Mark as Unread") { model?.markUnread() }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .disabled(model?.selection == nil)
            Button("Mark All in Group as Read") { model?.markAllRead() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(model?.group == nil)
            Divider()
            Button("Subscribe to Groups…") { model?.browsing = model?.server ?? Library.shared.servers.first }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(model == nil)
        }

        CommandGroup(replacing: .help) {
            Link("Eternal September, Free Usenet Access", destination: URL(string: "https://www.eternal-september.org")!)
            Link("Gmane, Mailing Lists as Newsgroups", destination: URL(string: "https://gmane.io")!)
            Link("The NNTP Protocol (RFC 3977)", destination: URL(string: "https://www.rfc-editor.org/rfc/rfc3977")!)
        }
    }
}
