import Foundation

/// A catalog provider failed. Surfaces as 502 `provider_unavailable` — never as a 500,
/// and never with the provider's own message.
struct ProviderError: Error, Equatable {
    enum Kind: Equatable {
        case notFound
        case unavailable
        case malformed
        /// The provider refused our credentials (401/403): a revoked user token, never retried.
        case unauthorized
        /// Any other 4xx, kept so a caller can explain it (Trakt's 420 account limit, 423 locked
        /// account). Never retried: asking again gets the same answer.
        case refused(Int)
    }

    let provider: String
    let kind: Kind

    /// The provider's name as people read it.
    var displayName: String {
        switch provider {
        case "anilist": "AniList"
        case "tmdb": "TMDB"
        case "openlibrary": "Open Library"
        case "trakt": "Trakt"
        case "mal": "MyAnimeList"
        case "tvmaze": "TVmaze"
        case "pogdesign": "Pogdesign CAT"
        case "thesportsdb": "TheSportsDB"
        case "lastfm": "Last.fm"
        case "listenbrainz": "ListenBrainz"
        default: provider
        }
    }

    /// AniList failing as a whole (down, disabled, answering garbage), not missing one entry.
    var isAniListOutage: Bool {
        provider == "anilist" && kind != .notFound
    }
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
    /// A provider's own reading of a failed answer, before the status-code rules: AniList says
    /// "disabled" with a 403, which is an outage, not a refused credential.
    var classify: (@Sendable (OutboundResponse) -> ProviderError.Kind?)?

    /// Longest `Retry-After` honoured; a longer one fails the call so a job can retry later.
    static let maxRetryAfter: Duration = .seconds(60)

    func data(_ request: OutboundRequest) async throws -> Data {
        try await response(request).body
    }

    /// The whole successful response, headers included (Trakt pages by `X-Pagination-*`).
    func response(_ request: OutboundRequest) async throws -> OutboundResponse {
        var attempt = 1
        while true {
            try Task.checkCancellation()
            try await pacer.acquire()
            let retryable: Bool
            var retryAfter: Duration?
            do {
                let response = try await transport.send(request)
                if (200 ..< 300).contains(response.status) {
                    return response
                }
                try refuse(response)
                retryable = response.status == 429 || (500 ..< 600).contains(response.status)
                if response.status == 429 {
                    retryAfter = response.header("Retry-After").flatMap(Int.init).map { .seconds($0) }
                }
            } catch let error as ProviderError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                retryable = true // network error
            }
            guard retryable, attempt < maxAttempts, (retryAfter ?? .zero) <= Self.maxRetryAfter else {
                throw ProviderError(provider: name, kind: .unavailable)
            }
            try await sleep(retryAfter ?? baseDelay * (1 << (attempt - 1)))
            attempt += 1
        }
    }

    /// Throws for the answers that asking again would not change: 404, 401/403, any other 4xx
    /// but 429.
    private func refuse(_ response: OutboundResponse) throws {
        if let kind = classify?(response) {
            throw ProviderError(provider: name, kind: kind)
        }
        switch response.status {
        case 404: throw ProviderError(provider: name, kind: .notFound)
        case 401, 403: throw ProviderError(provider: name, kind: .unauthorized)
        case 429: return
        case 400 ..< 500: throw ProviderError(provider: name, kind: .refused(response.status))
        default: return
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
