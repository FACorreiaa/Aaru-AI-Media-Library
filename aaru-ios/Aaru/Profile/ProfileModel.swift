import AaruAPI
import Foundation
import Observation

typealias ProfileStats = Components.Schemas.ProfileStats

/// GAM-006b, pulled forward without badges or points (2026-10-22): the profile's all-time
/// numbers from `/v1/me/profile/stats`, and who is signed in from `/v1/me`. All-time means the
/// library as it is, so undated and imported ticks count here and not in Insights.
@MainActor
@Observable
final class ProfileModel {
    private(set) var stats: ProfileStats?
    private(set) var account: Components.Schemas.Me?
    private(set) var isLoading = false
    /// The last load failed and there is nothing to show.
    private(set) var failed = false

    @ObservationIgnored private let api: Client?

    /// `account` is what Home already has, so the header shows at once.
    init(api: Client?, account: Components.Schemas.Me? = nil) {
        self.api = api
        self.account = account
    }

    /// For previews: the numbers already in place.
    convenience init(preview stats: ProfileStats, account: Components.Schemas.Me? = nil) {
        self.init(api: nil, account: account)
        self.stats = stats
    }

    func load() async {
        guard let api, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        async let meCall = api.getMe()
        async let statsCall = api.getProfileStats()
        if case let .ok(response)? = try? await meCall, let signedIn = try? response.body.json {
            account = signedIn
        }
        if case let .ok(response)? = try? await statsCall, let loaded = try? response.body.json {
            stats = loaded
            failed = false
        } else {
            failed = stats == nil
        }
    }

    /// Nothing watched, read or on the shelf yet: the empty state instead of a page of zeros.
    var isEmpty: Bool {
        guard let stats else { return false }
        let counts = [stats.shows, stats.anime, stats.movies, stats.books]
        return stats.minutesWatched == 0 && stats.episodesWatched == 0
            && counts.allSatisfy { $0.finished == 0 && $0.inProgress == 0 }
    }

    // MARK: Words

    /// "41 days, 6 hours", the way MAL counts it; "6 hours" or "45 minutes" under a day.
    nonisolated static func timeLabel(minutes: Int) -> String {
        let days = minutes / (24 * 60)
        let hours = minutes % (24 * 60) / 60
        func unit(_ count: Int, _ one: String) -> String {
            "\(count.formatted()) \(count == 1 ? one : one + "s")"
        }
        switch (days, hours) {
        case (0, 0): return unit(minutes, "minute")
        case (0, _): return unit(hours, "hour")
        case (_, 0): return unit(days, "day")
        default: return "\(unit(days, "day")), \(unit(hours, "hour"))"
        }
    }

    /// "990 hours · 4,812 episodes", leaving out what is zero.
    nonisolated static func totalsLine(minutes: Int, episodes: Int) -> String {
        let hours = minutes / 60
        return [
            hours > 0 ? "\(hours.formatted()) \(hours == 1 ? "hour" : "hours")" : nil,
            episodes > 0 ? "\(episodes.formatted()) \(episodes == 1 ? "episode" : "episodes")" : nil,
        ].compactMap(\.self).joined(separator: " · ")
    }

    /// "In Aaru since Oct 2026".
    nonisolated static func sinceLine(_ date: Date) -> String {
        "In Aaru since \(date.formatted(.dateTime.month(.abbreviated).year()))"
    }

    /// Two letters from the display name, else the handle's first, else nil.
    nonisolated static func initials(_ account: Components.Schemas.Me?) -> String? {
        let words = (account?.displayName ?? "").split(whereSeparator: \.isWhitespace)
        if words.count >= 2, let first = words[0].first, let second = words[1].first {
            return "\(first)\(second)".uppercased()
        }
        return (words.first?.first ?? account?.handle?.first).map { String($0).uppercased() }
    }
}
