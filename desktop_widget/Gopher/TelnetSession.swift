// TelnetSession — a small telnet client for Macs without one, run in Terminal by launching the
// app's own executable as `GopherBrowser --telnet host port`. It does what nc can't: answers
// the server's option negotiation (RFC 854 and 855). It lets the server echo and drop go-ahead,
// which is the character-at-a-time mode SDF and BBSes expect, tells it the terminal type and
// window size if asked, and refuses everything else. Control-] closes it, as in telnet.

import Darwin
import Foundation

enum TelnetSession {
    static func run(host: String, port: Int) -> Never {
        let socket = connect(host: host, port: port)
        guard socket >= 0 else {
            print("Couldn't connect to \(host), port \(port).")
            exit(1)
        }
        print("Connected. Control-] closes the session.")
        fflush(stdout)

        // Raw mode sends each key as it's pressed and leaves echoing to the server.
        var saved = termios()
        let terminal = tcgetattr(0, &saved) == 0
        if terminal {
            var raw = saved
            cfmakeraw(&raw)
            tcsetattr(0, TCSANOW, &raw)
        }

        var session = Negotiation(socket: socket)
        var fds = [pollfd(fd: 0, events: Int16(POLLIN), revents: 0),
                   pollfd(fd: socket, events: Int16(POLLIN), revents: 0)]
        var buffer = [UInt8](repeating: 0, count: 8192)
        loop: while true {
            if poll(&fds, 2, -1) < 0 {
                if errno == EINTR { continue }
                break
            }
            if fds[1].revents != 0 {
                let n = read(socket, &buffer, buffer.count)
                if n <= 0 { break }
                write(1, session.receive(buffer[..<n]))
            }
            if fds[0].revents != 0 {
                let n = read(0, &buffer, buffer.count)
                if n <= 0 { break }
                var out: [UInt8] = []
                for byte in buffer[..<n] {
                    switch byte {
                    case 0x1D: break loop                  // Control-]
                    case IAC: out += [IAC, IAC]
                    case 13: out += [13, 0]                // a bare CR is sent as CR NUL
                    default: out.append(byte)
                    }
                }
                write(socket, out)
            }
        }

        if terminal { tcsetattr(0, TCSANOW, &saved) }
        close(socket)
        print("\nConnection closed.")
        exit(0)
    }

    private static func connect(host: String, port: Int) -> Int32 {
        var hints = addrinfo()
        hints.ai_socktype = SOCK_STREAM
        var list: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &list) == 0 else { return -1 }
        defer { freeaddrinfo(list) }
        var next = list
        while let info = next {
            let fd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
            if fd >= 0 {
                if Darwin.connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0 { return fd }
                close(fd)
            }
            next = info.pointee.ai_next
        }
        return -1
    }

    /// Writes all of `bytes`, however many tries it takes.
    fileprivate static func write(_ fd: Int32, _ bytes: [UInt8]) {
        var sent = 0
        while sent < bytes.count {
            let n = bytes[sent...].withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
            if n < 0 && errno == EINTR { continue }
            if n <= 0 { return }
            sent += n
        }
    }
}

private let IAC: UInt8 = 255, DONT: UInt8 = 254, DO: UInt8 = 253, WONT: UInt8 = 252, WILL: UInt8 = 251
private let SB: UInt8 = 250, SE: UInt8 = 240
private let ECHO: UInt8 = 1, SGA: UInt8 = 3, TTYPE: UInt8 = 24, NAWS: UInt8 = 31

/// The server's side of the stream: text to show, with commands taken out and answered.
private struct Negotiation {
    enum State { case text, command, option(UInt8), sub, subCommand }

    let socket: Int32
    var state = State.text
    var sub: [UInt8] = []
    var afterCR = false
    /// Options the server does, and options this end does, once agreed.
    var theirs: Set<UInt8> = []
    var ours: Set<UInt8> = []

    mutating func receive(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
        var text: [UInt8] = []
        for byte in bytes {
            switch state {
            case .text:
                if byte == IAC {
                    state = .command
                } else if afterCR && byte == 0 {
                    afterCR = false                        // CR NUL is a bare CR
                } else {
                    text.append(byte)
                    afterCR = byte == 13
                }
            case .command:
                switch byte {
                case WILL, WONT, DO, DONT: state = .option(byte)
                case SB: sub = []; state = .sub
                case IAC: text.append(IAC); state = .text
                default: state = .text                     // go-ahead, no-op and the like
                }
            case .option(let verb):
                answer(verb, byte)
                state = .text
            case .sub:
                if byte == IAC { state = .subCommand } else { sub.append(byte) }
            case .subCommand:
                if byte == SE {
                    subnegotiate()
                    state = .text
                } else {
                    sub.append(byte)
                    state = .sub
                }
            }
        }
        return text
    }

    /// Agrees to what's wanted and refuses the rest, answering only a change, so neither end
    /// loops (RFC 1143's rule).
    private mutating func answer(_ verb: UInt8, _ option: UInt8) {
        switch verb {
        case WILL:
            if [ECHO, SGA].contains(option) {
                if theirs.insert(option).inserted { send([IAC, DO, option]) }
            } else {
                send([IAC, DONT, option])
            }
        case WONT:
            if theirs.remove(option) != nil { send([IAC, DONT, option]) }
        case DO:
            if [SGA, TTYPE, NAWS].contains(option) {
                if ours.insert(option).inserted { send([IAC, WILL, option]) }
                if option == NAWS { sendWindowSize() }
            } else {
                send([IAC, WONT, option])
            }
        default:
            if ours.remove(option) != nil { send([IAC, WONT, option]) }
        }
    }

    private func subnegotiate() {
        // The server asking for the terminal type: TTYPE SEND.
        if sub == [TTYPE, 1] {
            let type = ProcessInfo.processInfo.environment["TERM"] ?? "xterm-256color"
            send([IAC, SB, TTYPE, 0] + Array(type.utf8) + [IAC, SE])
        }
    }

    private func sendWindowSize() {
        var size = winsize()
        guard ioctl(1, TIOCGWINSZ, &size) == 0 else { return }
        var bytes: [UInt8] = []
        for value in [size.ws_col, size.ws_row] {
            for byte in [UInt8(value >> 8), UInt8(value & 0xFF)] {
                bytes += byte == IAC ? [IAC, IAC] : [byte]
            }
        }
        send([IAC, SB, NAWS] + bytes + [IAC, SE])
    }

    private func send(_ bytes: [UInt8]) {
        TelnetSession.write(socket, bytes)
    }
}
