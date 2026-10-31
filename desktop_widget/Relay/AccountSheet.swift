// AccountSheet — logging in to a registered nick, or registering the one in use, without
// typing NickServ commands. It sends them itself, never showing the password, keeps the
// account and password for SASL so later connections log in by themselves, and shows what
// NickServ says back, asking for the emailed code when NickServ wants one.

import SwiftUI
import AppKit

struct AccountSheet: View {
    enum Mode: String, CaseIterable { case logIn = "I Have an Account", register = "Register This Nick" }

    @ObservedObject var session: Session
    @State private var mode = Mode.logIn
    @State private var account = ""
    @State private var password = ""
    @State private var email = ""
    @State private var code = ""
    @State private var showPassword = false
    @State private var sent = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(session.account.map { "Logged in to \(session.network.name) as \($0)" } ?? "Your Nick on \(session.network.name)")
                .font(.title3.bold())

            if session.servicesMissing {
                Text("\(session.network.name) has no NickServ, so nicks here can't be registered. Anyone can use a nick "
                     + "that's free, so connect early to keep yours.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(sent)

                Form {
                    if mode == .logIn {
                        TextField("Account", text: $account, prompt: Text("usually your nick"))
                    } else {
                        LabeledContent("Nick") {
                            Text(session.nick)
                        }
                    }
                    if mode == .register && onFallback {
                        Text("You're on as \(session.nick) because \(session.preferredNick) was in use, and NickServ "
                             + "registers the nick you're using. If \(session.preferredNick) is already yours, log in "
                             + "to it instead and Relay Chat will take it back.")
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Group {
                            if showPassword {
                                TextField("Password", text: $password)
                            } else {
                                SecureField("Password", text: $password)
                            }
                        }
                        if mode == .register {
                            Button("Suggest") {
                                password = Self.randomPassword()
                                showPassword = true
                            }
                        }
                        Toggle("Show", isOn: $showPassword).toggleStyle(.checkbox)
                    }
                    if mode == .register {
                        TextField("Email", text: $email, prompt: Text("for the confirmation code; others don't see it"))
                    }
                }
                .formStyle(.columns)
                .disabled(sent && session.servicesFailure == nil)

                Text(footnote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if sent { progress }
            }

            HStack {
                if session.state != .connected {
                    Text("Connect to \(session.network.name) first.").foregroundStyle(.red)
                }
                Spacer()
                Button(done ? "Done" : "Cancel") { dismiss() }
                    .keyboardShortcut(done ? .defaultAction : .cancelAction)
                if !done && !session.servicesMissing {
                    Button(mode == .logIn ? "Log In" : "Register") { send() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!ready)
                }
            }
        }
        .padding(20)
        .frame(width: 500)
        .onAppear {
            account = session.network.account.isEmpty
                ? (session.preferredNick.isEmpty ? session.nick : session.preferredNick) : session.network.account
            password = Keychain.password(for: session.network) ?? ""
            mode = session.network.account.isEmpty && password.isEmpty ? .register : .logIn
        }
    }

    private var footnote: String {
        switch mode {
        case .logIn:
            "Relay Chat sends the password to NickServ, never to the log, and keeps it in your Keychain "
                + "so it can log you in by itself whenever it connects."
        case .register:
            "This registers \(session.nick) with \(session.network.name)'s NickServ, so only you can use it. Most "
                + "networks then email a code to confirm the address. The password goes in your Keychain; "
                + "use one you don't use anywhere else."
        }
    }

    /// Connected under a stand-in because the nick asked for was taken.
    private var onFallback: Bool {
        !session.preferredNick.isEmpty && session.nick.caseInsensitiveCompare(session.preferredNick) != .orderedSame
    }

    private var ready: Bool {
        guard session.state == .connected, !password.isEmpty, !sent || session.servicesFailure != nil else { return false }
        return mode == .logIn ? !account.trimmingCharacters(in: .whitespaces).isEmpty : email.contains("@")
    }

    /// Finished: logged in, or registered with nothing left to confirm.
    private var done: Bool {
        sent && session.servicesFailure == nil
            && (session.account != nil && !session.servicesNeedsCode || session.servicesConfirmed)
    }

    private func send() {
        sent = true
        if mode == .logIn {
            session.logIn(account: account.trimmingCharacters(in: .whitespaces), password: password)
        } else {
            session.register(password: password, email: email.trimmingCharacters(in: .whitespaces))
        }
    }

    @ViewBuilder private var progress: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let failure = session.servicesFailure {
                Label(failure, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            } else if done {
                Label("Done. Relay Chat will log you in as \(session.network.account) each time it connects.",
                      systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            } else if session.servicesNeedsCode {
                Text("NickServ has emailed a code. Paste it here to finish:")
                HStack {
                    TextField("Code", text: $code).textFieldStyle(.roundedBorder)
                    Button("Confirm") { session.confirm(code: code.trimmingCharacters(in: .whitespaces)) }
                        .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for NickServ…").foregroundStyle(.secondary)
                }
            }
            if !session.servicesLog.isEmpty {
                ScrollView {
                    Text(session.servicesLog.joined(separator: "\n"))
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 110)
                .padding(8)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    /// Sixteen characters from letters and digits that are hard to mistake for each other.
    static func randomPassword() -> String {
        let alphabet = Array("abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var generator = SystemRandomNumberGenerator()
        return String((0..<16).map { _ in alphabet.randomElement(using: &generator)! })
    }
}
