import Foundation

/// A catalog provider failed. Surfaces as 502 `provider_unavailable` — never as a 500,
/// and never with the provider's own message.
struct ProviderError: Error, Equatable {
    enum Kind: Equatable {
        case notFound
        case unavailable
        case malformed
    }

    let provider: String
    let kind: Kind
}

/// Token bucket shared by every caller of one provider (CAT-001, X-002), so two
/// concurrent imports cannot stampede it. Waiting is cancellable.
actor RequestPacer {
    private let ratePerSecond: Double
    private let burst: Double
    private var tokens: Double
    private var refilledAt: ContinuousClock.Instant
    private let clock = ContinuousClock()

    init(requestsPerSecond: Double, burst: Int) {
        ratePerSecond = requestsPerSecond
        self.burst = Double(burst)
        tokens = Double(burst)
        refilledAt = clock.now
    }

    func acquire() async throws {
        while true {
            refill()
            if tokens >= 1 {
                tokens -= 1
                return
            }
            let wait = (1 - tokens) / ratePerSecond
            try await Task.sleep(for: .milliseconds(Int(wait * 1000) + 1))
        }
    }

    private func refill() {
        let now = clock.now
        let elapsed = refilledAt.duration(to: now)
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        tokens = min(burst, tokens + seconds * ratePerSecond)
        refilledAt = now
    }
}

/// The one way adapters reach a provider: paced, retried with backoff on 429/5xx and
/// network errors, and cancelled with the calling task (a client that disconnects
/// cancels its provider calls).
struct ProviderClient: Sendable {
    let name: String
    let transport: any HTTPTransport
    let pacer: RequestPacer
    var maxAttempts = 3
    var baseDelay: Duration = .milliseconds(250)
    var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

    func data(_ request: OutboundRequest) async throws -> Data {
        var attempt = 1
        while true {
            try Task.checkCancellation()
            try await pacer.acquire()
            let retryable: Bool
            do {
                let response = try await transport.send(request)
                switch response.status {
                case 200 ..< 300:
                    return response.body
                case 404:
                    throw ProviderError(provider: name, kind: .notFound)
                case 429, 500 ..< 600:
                    retryable = true
                default:
                    retryable = false
                }
            } catch let error as ProviderError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                retryable = true // network error
            }
            guard retryable, attempt < maxAttempts else {
                throw ProviderError(provider: name, kind: .unavailable)
            }
            try await sleep(baseDelay * (1 << (attempt - 1)))
            attempt += 1
        }
    }

    func decode<T: Decodable>(
        _: T.Type,
        _ request: OutboundRequest,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        let body = try await data(request)
        do {
            return try decoder.decode(T.self, from: body)
        } catch {
            throw ProviderError(provider: name, kind: .malformed)
        }
    }
}
