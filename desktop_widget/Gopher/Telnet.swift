// Telnet — gopher's type 8 links and telnet:// ones lead to a login on a server rather than a
// page, so they're handed to Terminal as a .command script that deletes itself once it runs.
// macOS stopped shipping telnet in High Sierra, so the script uses Homebrew's if it's there,
// and this app's own small client (TelnetSession) otherwise.

import AppKit

enum Telnet {
    struct Failure: LocalizedError {
        var errorDescription: String?
    }

    /// Opens a session with `host` in a new Terminal window, logging in as `user` if there is one.
    /// The host and user come from servers' menus, so the host must look like a host name and
    /// both are quoted before the shell sees them.
    static func open(host: String, port: Int, user: String) throws {
        let hostCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-:_"))
        guard !host.isEmpty, host.unicodeScalars.allSatisfy(hostCharacters.contains), !host.hasPrefix("-"),
              (1...65535).contains(port) else {
            throw Failure(errorDescription: "“\(host)” isn't a server Gopher Browser can open a session with.")
        }
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            throw Failure(errorDescription: "Terminal isn't on this Mac.")
        }
        guard let app = Bundle.main.executablePath else {
            throw Failure(errorDescription: "Gopher Browser couldn't find itself to run the session.")
        }
        let user = user.trimmingCharacters(in: .whitespacesAndNewlines)
        let script = """
            #!/bin/zsh
            rm -f -- "$0"
            host=\(quote(host)) port=\(port) user=\(quote(user))
            print "Telnet to $host, port $port."
            login=()
            if [[ -n $user ]]; then login=(-l "$user"); print "Log in as $user."; fi
            for telnet in telnet /opt/homebrew/bin/telnet /usr/local/bin/telnet; do
                command -v $telnet >/dev/null && exec $telnet $login -- "$host" $port
            done
            exec \(quote(app)) --telnet "$host" $port

            """
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("Telnet \(host) \(UUID().uuidString.prefix(8)).command")
        try script.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        NSWorkspace.shared.open([file], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    /// `s` in single quotes, with any single quotes in it closed, escaped and reopened.
    private static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
