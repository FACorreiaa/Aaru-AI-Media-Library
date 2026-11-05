#if canImport(Network)
    import Foundation
    import Network
    import OpenAPIRuntime
    import Testing
    @testable import AaruAPI

    /// Resumed by the test once it holds the first frame; the server waits on it before the second.
    private actor Gate {
        private var open = false
        private(set) var timedOut = false
        private var waiter: CheckedContinuation<Void, Never>?

        func wait() async {
            if open {
                return
            }
            await withCheckedContinuation { waiter = $0 }
        }

        func timeOut() {
            timedOut = true
            release()
        }

        func release() {
            open = true
            waiter?.resume()
            waiter = nil
        }
    }

    /// A loopback server: answers any request with an event stream, one frame now, one after `gate`.
    private final class StreamServer: @unchecked Sendable {
        // @unchecked: test-only; the listener and connections are touched on `queue` only.
        private let queue = DispatchQueue(label: "chat-stream-server")
        private let listener: NWListener
        let gate = Gate()

        init() throws {
            listener = try NWListener(using: .tcp, on: .any)
        }

        func start() async throws -> UInt16 {
            listener.newConnectionHandler = { [gate] connection in
                connection.start(queue: self.queue)
                Self.serve(connection, gate: gate)
            }
            return try await withCheckedThrowingContinuation { continuation in
                listener.stateUpdateHandler = { [listener] state in
                    switch state {
                    case .ready:
                        listener.stateUpdateHandler = nil
                        continuation.resume(returning: listener.port?.rawValue ?? 0)
                    case let .failed(error):
                        listener.stateUpdateHandler = nil
                        continuation.resume(throwing: error)
                    default: break
                    }
                }
                listener.start(queue: queue)
            }
        }

        func stop() {
            listener.cancel()
        }

        private static func serve(_ connection: NWConnection, gate: Gate) {
            Exchange(connection: connection, gate: gate).readRequest()
        }
    }

    /// One accepted connection: reads the request head, then streams the answer.
    private final class Exchange: @unchecked Sendable {
        // @unchecked: test-only; `received` is touched only from the connection's serial queue.
        private let connection: NWConnection
        private let gate: Gate
        private var received = Data()

        init(connection: NWConnection, gate: Gate) {
            self.connection = connection
            self.gate = gate
        }

        func readRequest() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
                guard error == nil else { return self.connection.cancel() }
                self.received.append(data ?? Data())
                guard self.received.range(of: Data("\r\n\r\n".utf8)) != nil else { return self.readRequest() }
                self.respond()
            }
        }

        private func respond() {
            let head = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n\r\n"
            let first = "event: delta\ndata: {\"text\":\"one\"}\n\n"
            connection.send(content: Data((head + first).utf8), completion: .contentProcessed { _ in
                Task {
                    await self.gate.wait()
                    let second = "event: delta\ndata: {\"text\":\"two\"}\n\nevent: done\ndata: {\"turnId\":\"t\"}\n\n"
                    self.connection.send(
                        content: Data(second.utf8),
                        contentContext: .finalMessage,
                        isComplete: true,
                        completion: .contentProcessed { _ in self.connection.cancel() }
                    )
                }
            })
        }
    }

    struct ChatStreamingTransportTests {
        @Test func urlSessionTransportDeliversTheFirstFrameBeforeTheSecondIsSent() async throws {
            let server = try StreamServer()
            let port = try await server.start()
            defer { server.stop() }
            let gate = server.gate

            // Fails the test (and frees the server) if the first frame never arrives.
            let watchdog = Task {
                try await Task.sleep(for: .seconds(5))
                await gate.timeOut()
            }
            defer { watchdog.cancel() }

            let client = try Client.aaru(
                baseURL: #require(URL(string: "http://127.0.0.1:\(port)")),
                session: SessionMiddleware(token: { nil }, onUnauthorized: {})
            )
            let output = try await client.createChatTurn(.init(
                path: .init(id: "chat-1"),
                body: .json(.init(body: "hi"))
            ))
            let body = try output.ok.body.textEventStream

            var parser = ChatFrameParser()
            var texts: [String] = []
            var released = false
            for try await chunk in body {
                for frame in parser.consume(chunk) {
                    if case let .delta(text) = frame {
                        texts.append(text)
                    }
                }
                if !released, !texts.isEmpty {
                    released = true
                    await gate.release()
                }
            }
            #expect(texts == ["one", "two"])
            #expect(await gate.timedOut == false)
        }
    }
#endif
