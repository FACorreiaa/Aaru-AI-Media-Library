import Foundation

/// Fixed-window counter per key. In-process: the API runs one replica (see the
/// infra values). Move to Valkey when that changes.
actor FixedWindowRateLimiter {
    private let limit: Int
    private let window: TimeInterval
    private var windows: [String: (start: Date, count: Int)] = [:]

    init(limit: Int, window: TimeInterval) {
        self.limit = limit
        self.window = window
    }

    /// Records one attempt for `key` and returns whether it is within the limit.
    func allow(_ key: String, now: Date = .now) -> Bool {
        if windows.count > 10000 {
            windows = windows.filter { now.timeIntervalSince($0.value.start) < window }
        }
        var entry = windows[key] ?? (now, 0)
        if now.timeIntervalSince(entry.start) >= window {
            entry = (now, 0)
        }
        entry.count += 1
        windows[key] = entry
        return entry.count <= limit
    }
}
