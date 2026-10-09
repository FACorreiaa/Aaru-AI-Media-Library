import Foundation
import Testing
@testable import aaru

@Suite("Provider client (CAT-001)")
struct ProviderClientTests {
    let url = URL(string: "https://provider.test/x")!

    func client(_ transport: StubTransport, sleeps: SleepLog = SleepLog()) -> ProviderClient {
        var client = ProviderClient(
            name: "test",
            transport: transport,
            pacer: RequestPacer(requestsPerSecond: 1000, burst: 100)
        )
        client.sleep = { duration in sleeps.append(duration) }
        return client
    }

    final class SleepLog: @unchecked Sendable {
        // @unchecked: test-only; `lock` guards `values`.
        private let lock = NSLock()
        private var values: [Duration] = []
        var all: [Duration] {
            lock.withLock { values }
        }

        func append(_ duration: Duration) {
            lock.withLock { values.append(duration) }
        }
    }

    @Test("429 twice then 200 is retried with exponential backoff and succeeds")
    func retriesRateLimits() async throws {
        let counter = Counter()
        let transport = StubTransport { _ in
            counter.next() < 2 ? OutboundResponse(status: 429, body: Data()) : OutboundResponse(
                status: 200,
                body: Data("ok".utf8)
            )
        }
        let sleeps = SleepLog()
        let body = try await client(transport, sleeps: sleeps).data(OutboundRequest(url: url))
        #expect(String(bytes: body, encoding: .utf8) == "ok")
        #expect(transport.requests.count == 3)
        #expect(sleeps.all == [.milliseconds(250), .milliseconds(500)])
    }

    @Test("A provider that keeps failing is 'unavailable' after three attempts; 404 is not retried")
    func givesUp() async throws {
        let failing = StubTransport { _ in OutboundResponse(status: 503, body: Data()) }
        await #expect(throws: ProviderError(provider: "test", kind: .unavailable)) {
            _ = try await client(failing).data(OutboundRequest(url: url))
        }
        #expect(failing.requests.count == 3)

        let missing = StubTransport { _ in OutboundResponse(status: 404, body: Data()) }
        await #expect(throws: ProviderError(provider: "test", kind: .notFound)) {
            _ = try await client(missing).data(OutboundRequest(url: url))
        }
        #expect(missing.requests.count == 1)
    }

    @Test("Cancelling the caller cancels the in-flight provider call")
    func cancellationPropagates() async throws {
        let transport = HangingTransport()
        let client = ProviderClient(
            name: "test",
            transport: transport,
            pacer: RequestPacer(requestsPerSecond: 10, burst: 1)
        )
        let request = OutboundRequest(url: url)
        let task = Task { try await client.data(request) }
        await transport.waitUntilStarted()
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(await transport.wasCancelled)
    }

    final class Counter: @unchecked Sendable {
        // @unchecked: test-only; `lock` guards `value`.
        private let lock = NSLock()
        private var value = 0
        func next() -> Int {
            lock.withLock { defer { value += 1 }; return value }
        }
    }
}

/// A transport whose request never finishes until its task is cancelled.
actor HangingTransport: HTTPTransport {
    private var started = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var wasCancelled = false

    func send(_: OutboundRequest) async throws -> OutboundResponse {
        started = true
        waiters.forEach { $0.resume() }
        waiters = []
        do {
            try await Task.sleep(for: .seconds(60))
        } catch {
            wasCancelled = true
            throw CancellationError()
        }
        return OutboundResponse(status: 200, body: Data())
    }

    func waitUntilStarted() async {
        if started {
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }
}
