// Net — the one kind of request both protocols make: connect, send a line, read until the
// server closes. Gopher sends it over plain TCP and Gemini over TLS; the rest is the same.

import Foundation
import Network

enum Net {
    struct Failure: LocalizedError {
        var errorDescription: String?
    }

    /// Sends `request` and returns everything the server sends back before it closes.
    /// `progress` hears the bytes so far, on the main actor.
    static func fetch(host: String, port: Int, parameters: NWParameters, request: Data, limit: Int = 256 << 20,
                      progress: @escaping @MainActor (Int) -> Void = { _ in }) async throws -> Data {
        guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: port)), port.rawValue > 0 else {
            throw Failure(errorDescription: "\(port) isn't a port number.")
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: parameters)
        let fetch = Fetch(connection, request: request, limit: limit, progress: progress)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { fetch.start($0) }
        } onCancel: {
            fetch.cancel()
        }
    }

    /// One request's state, touched only on its own serial queue.
    private final class Fetch: @unchecked Sendable {
        private let connection: NWConnection
        private let request: Data
        private let limit: Int
        private let progress: @MainActor (Int) -> Void
        private let queue = DispatchQueue(label: "gopher.fetch")
        private var continuation: CheckedContinuation<Data, Error>?
        private var data = Data()
        private var lastByte = Date()

        init(_ connection: NWConnection, request: Data, limit: Int, progress: @escaping @MainActor (Int) -> Void) {
            self.connection = connection
            self.request = request
            self.limit = limit
            self.progress = progress
        }

        func start(_ continuation: CheckedContinuation<Data, Error>) {
            queue.async { [self] in
                self.continuation = continuation
                connection.stateUpdateHandler = { [self] state in
                    switch state {
                    case .ready:
                        connection.send(content: request, completion: .contentProcessed { [self] error in
                            if let error { finish(.failure(error)) }
                        })
                        receive()
                    case .waiting(let error), .failed(let error):
                        finish(.failure(Self.describe(error)))
                    case .cancelled:
                        finish(.failure(CancellationError()))
                    default:
                        break
                    }
                }
                connection.start(queue: queue)
                watch()
            }
        }

        func cancel() {
            queue.async { [self] in finish(.failure(CancellationError())) }
        }

        private func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [self] content, _, complete, error in
                if let content {
                    data.append(content)
                    lastByte = Date()
                    let count = data.count
                    Task { @MainActor [progress] in progress(count) }
                }
                if data.count > limit {
                    finish(.failure(Failure(errorDescription: "It's larger than \(limit >> 20) MB, so it was stopped.")))
                } else if complete {
                    finish(.success(data))
                } else if let error {
                    // A server that resets instead of closing (or, over TLS, closes without
                    // saying so) has usually sent it all.
                    data.isEmpty ? finish(.failure(Self.describe(error))) : finish(.success(data))
                } else {
                    receive()
                }
            }
        }

        /// Gives up on a server that stops sending for half a minute.
        private func watch() {
            queue.asyncAfter(deadline: .now() + 5) { [self] in
                guard continuation != nil else { return }
                if Date().timeIntervalSince(lastByte) > 30 {
                    finish(.failure(Failure(errorDescription: "The server stopped answering.")))
                } else {
                    watch()
                }
            }
        }

        private func finish(_ result: Result<Data, Error>) {
            guard let continuation else { return }
            self.continuation = nil
            connection.stateUpdateHandler = nil
            connection.cancel()
            continuation.resume(with: result)
        }

        private static func describe(_ error: NWError) -> Error {
            switch error {
            case .posix(.ECONNREFUSED): Failure(errorDescription: "The server refused the connection.")
            case .posix(.ETIMEDOUT): Failure(errorDescription: "The server didn't answer.")
            case .dns: Failure(errorDescription: "There's no server by that name.")
            case .tls: Failure(errorDescription: "The secure connection to the server failed.")
            default: Failure(errorDescription: error.localizedDescription)
            }
        }
    }
}
