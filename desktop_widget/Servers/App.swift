// Server List — a menu bar item listing your servers, like Finder's Go → Connect to
// Server: choose one to open a remote session. It has no window, Dock icon or place in
// Widget Bar; the menu also adds and removes servers.

import SwiftUI

@main
struct ServerListApp: App {
    var body: some Scene {
        MenuBarExtra("Server List", systemImage: "server.rack") {
            ServerMenu()
        }
    }
}

struct ServerMenu: View {
    @ObservedObject var list = ServerList.shared

    var body: some View {
        if list.servers.isEmpty {
            Text("No Servers")
        }
        ForEach(list.servers) { server in
            Button { list.open(server) } label: { Label(server.label, systemImage: server.symbol) }
        }
        Divider()
        Button("Add Server…") { list.promptToAdd() }
        // By the full address, since two servers on one host share a label.
        Menu("Remove") {
            ForEach(list.servers) { server in
                Button { list.remove(server) } label: { Label(server.id, systemImage: server.symbol) }
            }
        }
        .disabled(list.servers.isEmpty)
        Divider()
        Button("Quit Server List") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
