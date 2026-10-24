import AaruAPI
import Foundation

/// What the calendar shows (CAL-003, the web's CAL-002 filters): applied to entries already
/// loaded, so changing one never waits on the network. Stored with `@AppStorage` by the screen.
struct CalendarFilter: Equatable {
    enum Only: String, CaseIterable, Identifiable {
        case all, premieres, finales

        var id: Self {
            self
        }

        var label: String {
            switch self {
            case .all: "All episodes"
            case .premieres: "Premieres"
            case .finales: "Finales"
            }
        }
    }

    enum Kind: String, CaseIterable, Identifiable {
        case all, show, anime

        var id: Self {
            self
        }

        var label: String {
            switch self {
            case .all: "Shows and anime"
            case .show: "Shows"
            case .anime: "Anime"
            }
        }
    }

    /// CAL-005: how Week and Month lay out their episodes. A layout, not a filter: it hides
    /// nothing, so `isActive` leaves it out.
    enum Grouping: String, CaseIterable, Identifiable {
        case day, channel

        var id: Self {
            self
        }

        var label: String {
            switch self {
            case .day: "Day"
            case .channel: "Channel"
            }
        }
    }

    var hideWatched = false
    var only: Only = .all
    var kind: Kind = .all
    var grouping: Grouping = .day

    /// A filter hides something. Grouping by channel is not one.
    var isActive: Bool {
        hideWatched || only != .all || kind != .all
    }

    func matches(_ entry: CalendarEntry) -> Bool {
        if hideWatched, entry.watched {
            return false
        }
        switch only {
        case .all: break
        case .premieres: if entry.kind != .premiere {
                return false
            }
        case .finales: if entry.kind != .finale {
                return false
            }
        }
        switch kind {
        case .all: return true
        case .show: return !entry.title.isAnime
        case .anime: return entry.title.isAnime
        }
    }
}

/// One show's aired, unwatched episodes, for Missed: oldest first.
struct MissedShow: Identifiable {
    let id: String
    let title: Components.Schemas.TitleSummary
    let episodes: [CalendarEntry]

    /// "3 episodes · 2 h 15 min", the time when every runtime is known.
    var line: String {
        var parts = ["\(episodes.count) episode\(episodes.count == 1 ? "" : "s")"]
        let minutes = episodes.compactMap(\.runtimeMinutes)
        if minutes.count == episodes.count {
            let total = minutes.reduce(0, +)
            parts.append(total >= 60 ? "\(total / 60) h \(total % 60) min" : "\(total) min")
        }
        return parts.joined(separator: " · ")
    }

    /// Aired and not watched, one group per show, the show with the oldest miss first.
    static func catchUp(_ entries: [CalendarEntry], now: Date) -> [MissedShow] {
        let aired = entries.filter { !$0.watched && $0.airsAt <= now }
            .sorted { ($0.airsAt, $0.season, $0.number) < ($1.airsAt, $1.season, $1.number) }
        var order: [String] = []
        var groups: [String: [CalendarEntry]] = [:]
        for entry in aired {
            if groups[entry.libraryItemId] == nil {
                order.append(entry.libraryItemId)
            }
            groups[entry.libraryItemId, default: []].append(entry)
        }
        return order.compactMap { id in
            guard let episodes = groups[id], let first = episodes.first else { return nil }
            return MissedShow(id: id, title: first.title, episodes: episodes)
        }
    }
}

/// CAL-005, "Group by: Channel": one channel's or streamer's episodes.
struct AiringChannel: Identifiable {
    /// Where episodes air when the title names no network. Always the last group.
    static let other = "Other"

    let channel: String
    let entries: [CalendarEntry]

    var id: String {
        channel
    }

    /// The busiest channel first, then by name; "Other" (no network) last. Each channel's
    /// episodes in air order, then by season and episode.
    static func group(_ entries: [CalendarEntry]) -> [AiringChannel] {
        var byChannel: [String: [CalendarEntry]] = [:]
        for entry in entries {
            let network = entry.title.network?.trimmingCharacters(in: .whitespaces) ?? ""
            byChannel[network.isEmpty ? other : network, default: []].append(entry)
        }
        return byChannel.map { channel, list in
            AiringChannel(
                channel: channel,
                entries: list.sorted { ($0.airsAt, $0.season, $0.number) < ($1.airsAt, $1.season, $1.number) }
            )
        }
        .sorted { lhs, rhs in
            if (lhs.channel == other) != (rhs.channel == other) {
                return rhs.channel == other
            }
            if lhs.entries.count != rhs.entries.count {
                return lhs.entries.count > rhs.entries.count
            }
            return lhs.channel.localizedStandardCompare(rhs.channel) == .orderedAscending
        }
    }
}

extension CalendarEntry {
    /// "Thu 15 Oct · 9:00 PM", or "Thu 15 Oct" for a date-only air date (read in UTC so it never
    /// shifts a day): a row's detail when grouped by channel, where the channel is the heading.
    var dayAndTime: String {
        let day = airsAt.formatted(
            Date.FormatStyle(timeZone: airTimeKnown ? .current : .gmt)
                .weekday(.abbreviated).day().month(.abbreviated)
        )
        return [day, timeText].compactMap(\.self).joined(separator: " · ")
    }
}
