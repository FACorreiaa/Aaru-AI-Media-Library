import AaruCore
import Foundation

/// One item of a Stremio library, as `datastoreGet` returns it. Only the fields an import reads.
struct StremioLibraryItem: Decodable, Equatable, Sendable {
    struct State: Decodable, Equatable, Sendable {
        var lastWatched: String?
        var timeOffset: Int?
        var timesWatched: Int?
        var flaggedWatched: Int?
        /// The watched-episode bitfield (see `StremioWatched`).
        var watched: String?
    }

    var id: String
    var type: String
    var name: String
    /// Taken out of the library by the user.
    var removed: Bool?
    /// Played but never added: Stremio keeps these for Continue watching.
    var temp: Bool?
    var state: State?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case type, name, removed, temp, state
    }
}

/// Turns a Stremio library into import rows (IMP-016). Shared by the link-code import and the
/// export-file fallback (IMP-016, M6), so both read Stremio the same way.
enum StremioLibraryMapper {
    static func rows(_ items: [StremioLibraryItem]) -> [ImportRow] {
        items.compactMap(row)
    }

    static func row(_ item: StremioLibraryItem) -> ImportRow? {
        let type: MediaType
        switch item.type {
        case "movie": type = .movie
        case "series": type = .show
        default: return nil
        }
        let state = item.state ?? StremioLibraryItem.State()
        let watchedOnce = (state.timesWatched ?? 0) > 0 || (state.flaggedWatched ?? 0) > 0
        let started = (state.timeOffset ?? 0) > 0
        let ticks = state.watched.map { !$0.isEmpty } ?? false
        let temp = item.temp == true
        // Removed by hand: the user took it out of Stremio, so it does not come in.
        if item.removed == true, !temp {
            return nil
        }
        // Opened once and never played.
        if temp, !watchedOnce, !started, !ticks {
            return nil
        }

        var row = ImportRow(
            sourceKey: item.id, type: type, title: item.name, ids: ExternalIDs(), lists: []
        )
        if item.id.hasPrefix("tt"), item.id.dropFirst(2).allSatisfy(\.isNumber), item.id.count > 2 {
            row.ids.imdb = item.id
        } else {
            row.unsupported = "Stremio lists this under an add-on's own id (\(item.id.prefix { $0 != ":" })), "
                + "not an IMDb id. Add it by hand."
        }
        switch type {
        case .movie where watchedOnce:
            row.status = .finished
            row.finishedAt = state.lastWatched.flatMap(StremioAccount.date)
        case .movie where started:
            row.status = .inProgress
        case .show where watchedOnce || started || ticks:
            row.status = .inProgress
            row.stremioWatched = ticks ? state.watched : nil
        default:
            row.status = .wishlist
        }
        return row
    }
}
