// Settings — the nick to go by, and the networks: where each is, a nick of its own if it
// needs one, the SASL account for a registered nick with its password in the Keychain, and
// the channels to join on connecting.

import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            IdentitySettings()
                .tabItem { Label("Identity", systemImage: "person.crop.circle") }
            NetworkSettings()
                .tabItem { Label("Networks", systemImage: "network") }
        }
        .frame(width: 620, height: 460)
    }
}

struct IdentitySettings: View {
    @AppStorage("nick") private var nick = ""
    @AppStorage("realName") private var realName = ""

    var body: some View {
        Form {
            Section {
                TextField("Nick", text: $nick, prompt: Text("what people will call you"))
                TextField("Real name", text: $realName, prompt: Text("optional; anyone can see it"))
            } footer: {
                Text("Nicks are letters, digits and a few marks such as _ - [ ] { } |, with no spaces, and "
                     + "usually up to 16 characters. If yours is taken when you connect, an underscore is added. "
                     + "To keep a nick as yours, register it with the network's NickServ and put the account in "
                     + "Networks.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

struct NetworkSettings: View {
    @ObservedObject private var chat = Chat.shared
    @State private var selection: UUID?
    @State private var draft: Network?
    @State private var password = ""
    @State private var channels = ""

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(chat.networks, selection: $selection) { network in
                    Text(network.name.isEmpty ? network.host : network.name).tag(network.id)
                }
                Divider()
                HStack(spacing: 0) {
                    Button { selection = chat.addNetwork().id } label: { Image(systemName: "plus").frame(width: 24, height: 20) }
                    Button {
                        if let network = chat.networks.first(where: { $0.id == selection }) {
                            chat.remove(network)
                            selection = chat.networks.first?.id
                        }
                    } label: { Image(systemName: "minus").frame(width: 24, height: 20) }
                        .disabled(selection == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(4)
            }
            .frame(width: 170)
            Divider()
            if draft != nil {
                form
            } else {
                Text("Choose a network, or add one with +.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { if selection == nil { selection = chat.networks.first?.id } }
        .onChange(of: selection, initial: true) { load() }
        .onChange(of: draft) { if let draft { chat.update(draft) } }
    }

    private func load() {
        draft = chat.networks.first { $0.id == selection }
        password = draft.flatMap(Keychain.password) ?? ""
        channels = draft?.channels.joined(separator: " ") ?? ""
    }

    @ViewBuilder private var form: some View {
        let network = Binding { draft! } set: { draft = $0 }
        Form {
            Section {
                TextField("Name", text: network.name)
                TextField("Server", text: network.host)
                TextField("Port", value: network.port, format: .number.grouping(.never))
                Toggle("Secure connection (TLS)", isOn: network.secure)
                    .onChange(of: network.wrappedValue.secure) { _, secure in
                        if secure && network.wrappedValue.port == 6667 { draft?.port = 6697 }
                        if !secure && network.wrappedValue.port == 6697 { draft?.port = 6667 }
                    }
                TextField("Channels to join", text: $channels, prompt: Text("#one #two"))
                    .onSubmit(saveChannels)
                    .onChange(of: channels) { saveChannels() }
            }
            Section {
                TextField("Nick here", text: network.nick, prompt: Text("the one in Identity"))
                TextField("SASL account", text: network.account, prompt: Text("none: connect as a guest"))
                SecureField("Password", text: $password)
                    .onChange(of: password) { if let draft { Keychain.setPassword(password, for: draft) } }
            } footer: {
                Text("Changes to the server, port, nick or account take effect the next time you connect. "
                     + "The account is usually your registered nick; the password goes in your Keychain.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    private func saveChannels() {
        let list = channels.split { $0 == " " || $0 == "," }.map { name in
            let name = String(name)
            return "#&".contains(name.first ?? " ") ? name : "#" + name
        }
        if draft?.channels != list { draft?.channels = list }
    }
}
