import Foundation
import Logging

/// SPT-001 · sports answers by key, each with its own freshness (livescores 90 s, a schedule
/// 30 min, a team a day). Shared by every user: two fans of one team cost one call. A failed
/// refresh keeps the stale copy and is not retried for a minute. Fetches are unstructured on
/// purpose: a caller giving up (a deadline, a disconnect) never cancels them, so the next
/// request finds the answer. Bounded: the oldest entries go first.
actor SportsCache {
    static let retryAfter: TimeInterval = 60
    static let maxEntries = 3000

    private struct Entry {
        var value: any Sendable
        var fetchedAt: Date
        var ttl: TimeInterval
    }

    private var entries: [String: Entry] = [:]
    private var failedAt: [String: Date] = [:]
    private var inFlight: [String: Task<any Sendable, any Error>] = [:]
    private let logger = Logger(label: "aaru-server")

    /// The fresh answer, fetching it if needed; a stale copy when the fetch fails.
    func value<T: Sendable>(
        _ key: String, ttl: TimeInterval, now: Date, fetch: @escaping @Sendable () async throws -> T
    ) async -> T? {
        guard let task = prime(key, ttl: ttl, now: now, fetch: fetch) else { return cached(key) }
        return await (try? task.value) as? T ?? cached(key)
    }

    /// Starts a fetch when the key is missing or expired, unless one is running or just failed.
    /// Returns the running fetch, if any.
    @discardableResult
    func prime<T: Sendable>(
        _ key: String, ttl: TimeInterval, now: Date, fetch: @escaping @Sendable () async throws -> T
    ) -> Task<any Sendable, any Error>? {
        if let entry = entries[key], now.timeIntervalSince(entry.fetchedAt) < entry.ttl {
            return nil
        }
        if let running = inFlight[key] {
            return running
        }
        if let failed = failedAt[key], now.timeIntervalSince(failed) < Self.retryAfter {
            return nil
        }
        let task = Task<any Sendable, any Error> {
            do {
                let value = try await fetch()
                self.store(key, value: value, ttl: ttl, now: now)
                return value
            } catch {
                self.fail(key, error: error, now: now)
                throw error
            }
        }
        inFlight[key] = task
        return task
    }

    /// Whatever is held for the key, fresh or stale.
    func cached<T: Sendable>(_ key: String) -> T? {
        entries[key]?.value as? T
    }

    /// Whether the key has ever been answered (stale counts).
    func has(_ key: String) -> Bool {
        entries[key] != nil
    }

    /// Waits until none of `keys` is being fetched, or `timeout` passes.
    func settle(_ keys: [String], timeout: Duration) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while keys.contains(where: { inFlight[$0] != nil }), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func store(_ key: String, value: any Sendable, ttl: TimeInterval, now: Date) {
        inFlight[key] = nil
        failedAt[key] = nil
        entries[key] = Entry(value: value, fetchedAt: now, ttl: ttl)
        trim()
    }

    private func fail(_ key: String, error: any Error, now: Date) {
        inFlight[key] = nil
        failedAt[key] = now
        logger.warning("Sports lookup failed", metadata: [
            "query": "\(key.prefix { $0 != ":" })", "error": "\(error)",
        ])
    }

    private func trim() {
        guard entries.count > Self.maxEntries else { return }
        let oldest = entries.sorted { $0.value.fetchedAt < $1.value.fetchedAt }.prefix(entries.count - Self.maxEntries)
        for (key, _) in oldest {
            entries[key] = nil
        }
    }
}
