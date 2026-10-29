// Server List — a small floating list of servers that opens a remote session on click,
// like Finder's Go → Connect to Server.

import SwiftUI

@main
enum ServerListApp {
    @MainActor static func main() {
        // Sized for the saved servers, and grows or shrinks as they change; starts just
        // left of Word Clock.
        DesktopClock.run(size: ServerListView.size(for: ServerList.shared.servers.count),
                         defaultTop: 24 + 170 + 20, defaultRight: 24 + 250 + 20) {
            ServerListView()
        } options: {
            ServerOptions()
        }
    }
}

struct ServerOptions: View {
    @ObservedObject var list = ServerList.shared

    var body: some View {
        Button("Add Server…") { list.promptToAdd() }
        // By the full address, since two servers on one host share a label.
        Menu("Remove") {
            ForEach(list.servers) { server in
                Button { list.remove(server) } label: { Label(server.id, systemImage: server.symbol) }
            }
        }
        .disabled(list.servers.isEmpty)
        Divider()
    }
}
