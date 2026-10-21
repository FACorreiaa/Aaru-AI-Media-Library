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

    var hideWatched = false
    var only: Only = .all
    var kind: Kind = .all

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
