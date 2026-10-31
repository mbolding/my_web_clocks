// Settings — the servers to read from, with their logins, and the name and address posts
// go out under. Passwords go to the Keychain as they're typed.

import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            ServerSettings()
                .tabItem { Label("Servers", systemImage: "server.rack") }
            PostingSettings()
                .tabItem { Label("Posting", systemImage: "square.and.pencil") }
        }
        .frame(width: 600, height: 420)
    }
}

struct ServerSettings: View {
    @ObservedObject private var library = Library.shared
    @State private var selection: UUID?
    @State private var password = ""

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(library.servers, selection: $selection) { server in
                    Text(server.name.isEmpty ? server.host : server.name).tag(server.id)
                }
                Divider()
                HStack(spacing: 0) {
                    Button { add() } label: { Image(systemName: "plus").frame(width: 24, height: 20) }
                    Button { remove() } label: { Image(systemName: "minus").frame(width: 24, height: 20) }
                        .disabled(selection == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(4)
            }
            .frame(width: 180)
            Divider()
            if let index = library.servers.firstIndex(where: { $0.id == selection }) {
                form(index)
            } else {
                Text("Choose a server, or add one with +.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { if selection == nil { selection = library.servers.first?.id } }
        .onChange(of: selection, initial: true) {
            password = library.servers.first { $0.id == selection }.flatMap(Keychain.password) ?? ""
        }
    }

    private func form(_ index: Int) -> some View {
        let server = $library.servers[index]
        return Form {
            TextField("Name", text: server.name)
            TextField("Server", text: server.host)
            TextField("Port", value: server.port, format: .number.grouping(.never))
            Toggle("Secure connection (TLS)", isOn: server.secure)
                .onChange(of: server.wrappedValue.secure) { _, secure in
                    if secure && server.wrappedValue.port == 119 { server.wrappedValue.port = 563 }
                    if !secure && server.wrappedValue.port == 563 { server.wrappedValue.port = 119 }
                }
            Section {
                TextField("User name", text: server.username, prompt: Text("None"))
                SecureField("Password", text: $password)
                    .onChange(of: password) { Keychain.setPassword(password, for: server.wrappedValue) }
            } footer: {
                Text(footer(server.wrappedValue))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    private func footer(_ server: Server) -> String {
        if server.host.contains("eternal-september") {
            return "Eternal September carries the whole of Usenet, free, but needs an account even to read. "
                + "Register at eternal-september.org; the password is kept in your Keychain."
        }
        if !server.secure && !server.username.isEmpty {
            return "Without a secure connection the password crosses the network as plain text."
        }
        return "Leave the user name empty for servers anyone can read. A password is kept in your Keychain."
    }

    private func add() {
        let server = Server(name: "New Server", host: "", port: 563, secure: true)
        library.servers.append(server)
        selection = server.id
    }

    private func remove() {
        guard let server = library.servers.first(where: { $0.id == selection }) else { return }
        library.removeServer(server)
        selection = library.servers.first?.id
    }
}

struct PostingSettings: View {
    @AppStorage("name") private var name = ""
    @AppStorage("email") private var email = ""
    @AppStorage("signature") private var signature = ""

    var body: some View {
        Form {
            Section {
                TextField("Your name", text: $name)
                TextField("Your address", text: $email, prompt: Text("you@example.org"))
            } footer: {
                Text("Every post carries these where anyone can read them, spammers included, which is why "
                     + "many people post under an address that only they can make out, such as "
                     + "you@example.org.invalid.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Signature") {
                TextEditor(text: $signature)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 70)
            }
        }
        .formStyle(.grouped)
    }
}
