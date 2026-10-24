import AaruCore
import Foundation
import Logging

/// The broadcaster or streamer a show premieres on, which is what a viewer tunes to.
struct OnAirChannel: Sendable, Equatable {
    var name: String
    var logoURL: URL?
}

/// The next episode of an on-air show. `airsAt` is a UTC day until a time is known.
struct OnAirEpisode: Sendable, Equatable {
    var season: Int
    var number: Int
    var name: String?
    var airsAt: Date
    var airTimeKnown = false
}

/// One streaming service (CAT-014). Data from JustWatch through TMDB, which must be credited.
struct WatchProvider: Sendable, Equatable {
    var name: String
    var logoURL: URL?
}

/// Where a title streams in one region: the services, and TMDB's page listing them all.
struct WatchProviders: Sendable, Equatable {
    var link: URL?
    var streaming: [WatchProvider]
}

/// One show airing this week (DISC-003), as the provider lists it: the same for every user.
struct OnAirShow: Sendable, Equatable {
    var hit: CatalogHit
    var channel: OnAirChannel?
    var next: OnAirEpisode
    /// By ISO 3166-1 region code, every region at once, so one cache serves all of them.
    var providers: [String: WatchProviders] = [:]
}

/// The shows airing this week, with their next episode and where they stream.
protocol OnAirListing: Sendable {
    func onAir(now: Date) async throws -> [OnAirShow]
}

/// An exact air time for a show's next episode (TVmaze, CAT-011).
protocol NextEpisodeTiming: Sendable {
    func nextAirTime(ids: ExternalIDs) async throws -> Date?
}

/// One show of the guide as one caller sees it: marked against their library, for their region.
struct OnAirEntry: Sendable, Equatable {
    var item: DiscoverItem
    var next: OnAirEpisode
    var streamsOn: [WatchProvider]
    var watchLink: URL?
}

struct OnAirGroup: Sendable, Equatable {
    var channel: OnAirChannel
    var shows: [OnAirEntry]
}

struct OnAirGuide: Sendable, Equatable {
    var channels: [OnAirGroup]
    var updatedAt: Date?
}

extension DiscoverService {
    /// Shows airing this week, one group per channel (DISC-003). An empty guide when the
    /// provider is down and nothing is cached.
    func onAir(userID: UserID, region: String?) async throws -> OnAirGuide {
        guard let onAirSource else { return OnAirGuide(channels: []) }
        let now = now()
        let timing = nextEpisodeTiming
        guard let fetched = await onAirCache.shows(
            now: now,
            fetch: { try await onAirSource.onAir(now: now) },
            refine: { shows in await Self.refine(shows, timing: timing) }
        ) else { return OnAirGuide(channels: []) }
        let marked = try await mark(fetched.shows.map(\.hit), userID: userID)
        let entries = zip(fetched.shows, marked).map { show, item in
            let local = region.flatMap { show.providers[$0] }
            return (show.channel, OnAirEntry(
                item: item, next: show.next,
                streamsOn: Self.streamsOn(local?.streaming ?? [], channel: show.channel),
                watchLink: local?.link
            ))
        }
        return OnAirGuide(channels: Self.grouped(entries), updatedAt: fetched.fetchedAt)
    }

    /// The name used for shows with no known channel. Always the last group.
    static let otherChannel = "Other"
    /// "Streams on" lists at most this many services.
    static let streamsOnLimit = 3

    /// Channels with the most shows first, then by name, "Other" last; shows by next air time.
    static func grouped(_ entries: [(OnAirChannel?, OnAirEntry)]) -> [OnAirGroup] {
        var groups: [String: OnAirGroup] = [:]
        for (channel, entry) in entries {
            let channel = channel ?? OnAirChannel(name: otherChannel)
            groups[channel.name, default: OnAirGroup(channel: channel, shows: [])].shows.append(entry)
        }
        return groups.values
            .map { group in
                var group = group
                group.shows.sort { ($0.next.airsAt, $0.item.hit.title) < ($1.next.airsAt, $1.item.hit.title) }
                return group
            }
            .sorted { lhs, rhs in
                let lhsOther = lhs.channel.name == otherChannel, rhsOther = rhs.channel.name == otherChannel
                if lhsOther != rhsOther {
                    return rhsOther
                }
                if lhs.shows.count != rhs.shows.count {
                    return lhs.shows.count > rhs.shows.count
                }
                return lhs.channel.name.localizedCaseInsensitiveCompare(rhs.channel.name) == .orderedAscending
            }
    }

    /// The services a show also streams on, without the channel itself ("Netflix" on Netflix) or
    /// the resellers JustWatch lists beside the service ("… Amazon Channel", "… with Ads").
    static func streamsOn(_ providers: [WatchProvider], channel: OnAirChannel?) -> [WatchProvider] {
        let resellers = ["amazon channel", "apple tv channel", "roku premium channel", "with ads"]
        let own = channel?.name.lowercased()
        var seen: Set<String> = []
        return Array(providers.filter { provider in
            let name = provider.name.lowercased()
            if let own, name.hasPrefix(own) || own.hasPrefix(name) {
                return false
            }
            if resellers.contains(where: name.contains) {
                return false
            }
            return seen.insert(name).inserted
        }.prefix(streamsOnLimit))
    }

    /// Exact times for the next episodes, one show at a time through the provider's pacer. A
    /// time is kept only within `TVmazeAirTimes.dateTolerance` of the listed day, as for the
    /// calendar, since the two catalogs can number a season differently.
    static func refine(_ shows: [OnAirShow], timing: (any NextEpisodeTiming)?) async -> [OnAirShow] {
        guard let timing else { return shows }
        var refined = shows
        for (index, show) in shows.enumerated() {
            guard !Task.isCancelled else { break }
            guard let stamp = try? await timing.nextAirTime(ids: show.hit.ids),
                  abs(stamp.timeIntervalSince(show.next.airsAt)) <= TVmazeAirTimes.dateTolerance
            else { continue }
            refined[index].next.airsAt = stamp
            refined[index].next.airTimeKnown = true
        }
        return refined
    }
}

/// The guide as fetched, shared by every user. The API runs one replica, so memory is enough.
/// A stale guide is served while a fresh one is fetched; exact times arrive in a second pass
/// after the guide is first published, so no viewer waits on TVmaze's pacer.
actor OnAirCache {
    struct Fetched: Sendable {
        var shows: [OnAirShow]
        var fetchedAt: Date
    }

    static let ttl: TimeInterval = DiscoverService.ttl

    private var fetched: Fetched?
    private var failedAt: Date?
    private var inFlight: Task<Fetched, any Error>?
    private let logger = Logger(label: "aaru-server")

    /// The cached guide when fresh. A stale one is returned at once while a refetch runs; with
    /// none, the caller waits on the fetch (the refine pass never). Nil when there is nothing.
    func shows(
        now: Date,
        fetch: @escaping @Sendable () async throws -> [OnAirShow],
        refine: @escaping @Sendable ([OnAirShow]) async -> [OnAirShow]
    ) async -> Fetched? {
        if let fetched, now.timeIntervalSince(fetched.fetchedAt) < Self.ttl {
            return fetched
        }
        if let failedAt, now.timeIntervalSince(failedAt) < DiscoverService.retryAfter {
            return fetched
        }
        let task = inFlight ?? start(now: now, fetch: fetch, refine: refine)
        if let fetched {
            return fetched
        }
        return try? await task.value
    }

    /// Unstructured on purpose: one caller disconnecting must not cancel everyone's fetch.
    private func start(
        now: Date,
        fetch: @escaping @Sendable () async throws -> [OnAirShow],
        refine: @escaping @Sendable ([OnAirShow]) async -> [OnAirShow]
    ) -> Task<Fetched, any Error> {
        let task = Task { try await Fetched(shows: fetch(), fetchedAt: now) }
        inFlight = task
        Task {
            do {
                let fresh = try await task.value
                settle(fresh)
                let refined = await refine(fresh.shows)
                publish(refined, fetchedAt: fresh.fetchedAt)
            } catch {
                inFlight = nil
                failedAt = now
                logger.warning("On-air guide failed", metadata: ["error": "\(error)"])
            }
        }
        return task
    }

    private func settle(_ fresh: Fetched) {
        inFlight = nil
        failedAt = nil
        fetched = fresh
    }

    /// Exact times replace the dates only if no newer guide landed meanwhile.
    private func publish(_ shows: [OnAirShow], fetchedAt: Date) {
        guard fetched?.fetchedAt == fetchedAt else { return }
        fetched?.shows = shows
    }
}
