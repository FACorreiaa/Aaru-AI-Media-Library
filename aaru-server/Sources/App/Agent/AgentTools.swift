import aaruAPI
import AaruCore
import Foundation

/// A tool call the caller cannot make, or made wrong. The message is safe to show the agent,
/// which will repeat it to the user.
struct AgentToolError: Error, Sendable, Equatable {
    var message: String

    static let readOnly = AgentToolError(message: """
    This connection is read-only. The user can allow changes for it in Aaru → Settings → Connections.
    """)
}

/// AG-001 · the tools an outside agent reaches, transport-neutral. Each one is a thin wrapper
/// over the service a `/v1` route calls, with the caller's scopes checked first; results are the
/// `/v1` DTOs, so no provider JSON leaks. MCP (`Sources/App/MCP`) is one transport over this.
struct AgentTools: Sendable {
    /// A direct write is one item and at most one episode, as a tap is (X-009).
    static let maxChanges = 100
    static let maxLibraryPage = 50
    static let maxAirsDays = 42

    let services: Services
    let stores: Stores
    var now: @Sendable () -> Date = { Date() }

    // MARK: search_titles

    struct SearchInput: Decodable, Sendable {
        var query: String?
        var type: String?
        var titleId: String?
    }

    struct SearchResult: Encodable, Sendable {
        var items: [Components.Schemas.CatalogHit]
        var incomplete: Bool
    }

    func searchTitles(_ input: SearchInput, caller: AgentCaller) async throws -> any Encodable & Sendable {
        try require(.libraryRead, caller)
        if let raw = input.titleId {
            guard input.query == nil else { throw AgentToolError(message: "Pass either query or titleId, not both.") }
            guard let id = TitleID(uuidString: raw) else { throw AgentToolError(message: "That titleId is not valid.") }
            return try await Components.Schemas.TitleDetail(services.catalog.detail(id))
        }
        let query = input.query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard (1 ... 200).contains(query.count) else {
            throw AgentToolError(message: "query must be 1 to 200 characters.")
        }
        guard let scope = SearchScope(rawValue: input.type ?? "all") else {
            throw AgentToolError(message: "type must be one of all, movie, show, anime, book.")
        }
        let result = try await services.catalog.search(query: query, scope: scope)
        return SearchResult(
            items: result.hits.map { Components.Schemas.CatalogHit($0) }, incomplete: result.incomplete
        )
    }

    // MARK: read_library

    struct LibraryInput: Decodable, Sendable {
        var libraryItemId: String?
        var status: Components.Schemas.LibraryStatus?
        var type: Components.Schemas.MediaType?
        var anime: Bool?
        var owned: Bool?
        var listId: String?
        var shelfId: String?
        var cursor: String?
        var limit: Int?
    }

    struct LibraryPage: Encodable, Sendable {
        var items: [Components.Schemas.LibraryEntry]
        var nextCursor: String?
    }

    func readLibrary(_ input: LibraryInput, caller: AgentCaller) async throws -> any Encodable & Sendable {
        try require(.libraryRead, caller)
        if let raw = input.libraryItemId {
            let entry = try await services.library.entry(itemID(raw), userID: caller.userID)
            return try await Components.Schemas.LibraryEntry.withWatched(entry, stores: stores)
        }
        let limit = input.limit ?? 20
        guard (1 ... Self.maxLibraryPage).contains(limit) else {
            throw AgentToolError(message: "limit must be between 1 and \(Self.maxLibraryPage).")
        }
        let page: (entries: [LibraryEntry], next: String?)
        if let raw = input.shelfId {
            guard let shelf = UUID(uuidString: raw) else { throw AgentToolError(message: "That shelfId is not valid.") }
            page = try await services.shelves.items(shelf, userID: caller.userID, cursor: input.cursor, limit: limit)
        } else {
            var filter = LibraryFilter()
            filter.status = input.status.map(LibraryStatus.init)
            filter.type = input.type.map(MediaType.init)
            filter.isAnime = input.anime
            filter.isOwned = input.owned
            if let raw = input.listId {
                guard let list = ListID(uuidString: raw)
                else { throw AgentToolError(message: "That listId is not valid.") }
                filter.listID = list
            }
            page = try await services.library.list(
                userID: caller.userID, filter: filter, cursor: input.cursor, limit: limit
            )
        }
        return LibraryPage(items: page.entries.map(Components.Schemas.LibraryEntry.init), nextCursor: page.next)
    }

    // MARK: list_airs

    struct AirsInput: Decodable, Sendable {
        var view: String?
        var from: String?
        // swiftlint:disable:next identifier_name
        var to: String?
    }

    struct Calendar: Encodable, Sendable {
        var items: [Components.Schemas.CalendarEntry]
    }

    func listAirs(_ input: AirsInput, caller: AgentCaller) async throws -> any Encodable & Sendable {
        try require(.libraryRead, caller)
        switch input.view ?? "calendar" {
        case "up_next":
            guard input.from == nil, input.to == nil else {
                throw AgentToolError(message: "from and to apply to the calendar view only.")
            }
            return try await Components.Schemas.UpNext(services.schedule.upNext(userID: caller.userID))
        case "calendar":
            let from = try input.from.map { try Self.date($0, name: "from") } ?? now()
            let until = try input.to.map { try Self.date($0, name: "to") } ?? from.addingTimeInterval(7 * 86400)
            guard until > from, until.timeIntervalSince(from) <= Double(Self.maxAirsDays) * 86400 else {
                throw AgentToolError(message: "to must be after from, and at most \(Self.maxAirsDays) days later.")
            }
            let entries = try await services.schedule.calendar(userID: caller.userID, from: from, until: until)
            return Calendar(items: entries.map(Components.Schemas.CalendarEntry.init))
        default:
            throw AgentToolError(message: "view must be calendar or up_next.")
        }
    }

    // MARK: apply_library_patch

    struct PatchApplied: Encodable, Sendable {
        var applied = true
        var item: Components.Schemas.LibraryEntry?
    }

    /// A change bigger than a tap: nothing was written; the user decides in Aaru.
    struct PlanProposed: Encodable, Sendable {
        var applied = false
        var status = "pending_approval"
        var planId: String
        var summary: String
        var changes: Int
        var expiresAt: Date
        var message = """
        Nothing has changed yet. The user was asked to approve this in Aaru; tell them it is waiting there.
        """
    }

    func applyLibraryPatch(_ input: AgentPatchInput, caller: AgentCaller) async throws -> any Encodable & Sendable {
        try require(.libraryWrite, caller)
        let changes = try AgentChange.parse(input)
        guard changes.count == 1, let change = changes.first, change.isTapSized else {
            let plan = try await services.plans.propose(changes, caller: caller)
            return PlanProposed(
                planId: plan.id.uuidString.lowercased(), summary: plan.summary, changes: plan.changes.count,
                expiresAt: plan.expiresAt
            )
        }
        return try await apply(change, caller: caller)
    }

    /// One tap-sized change, journaled as the token.
    private func apply(_ change: AgentChange, caller: AgentCaller) async throws -> PatchApplied {
        let agent = Caller.agent(caller.token)
        let library = services.library
        let entry: LibraryEntry
        switch change {
        case let .add(ref, status):
            entry = try await library.add(ref, status: status, userID: caller.userID, by: agent)
        case let .update(id, patch):
            entry = try await library.patch(id, userID: caller.userID, patch: patch, by: agent)
        case let .episodes(id, keys, season, watched):
            if let season {
                entry = try await library.markSeasonWatched(id, userID: caller.userID, season: season, by: agent)
            } else if keys.count == 1 {
                // A single tick validates the episode, as the route does.
                entry = try await library.setEpisode(
                    id, userID: caller.userID, key: keys[0], watched: watched, by: agent
                )
            } else if let changed = try await library.setEpisodes(
                id, userID: caller.userID, keys: keys, watched: watched, by: agent
            ) {
                entry = changed
            } else {
                entry = try await library.entry(id, userID: caller.userID)
            }
        case let .remove(id):
            try await library.delete(id, userID: caller.userID, by: agent)
            return PatchApplied(item: nil)
        }
        return try await PatchApplied(item: .withWatched(entry, stores: stores))
    }

    // MARK: Helpers

    private func require(_ scope: AgentScope, _ caller: AgentCaller) throws {
        guard caller.has(scope) else {
            throw scope == .libraryWrite ? AgentToolError.readOnly
                : AgentToolError(message: "This connection cannot read the library.")
        }
    }

    private func itemID(_ raw: String) throws -> LibraryItemID {
        guard let id = LibraryItemID(uuidString: raw) else {
            throw AgentToolError(message: "That libraryItemId is not valid.")
        }
        return id
    }

    /// `2026-10-20` (UTC midnight) or a full ISO 8601 date-time.
    static func date(_ raw: String, name: String) throws -> Date {
        if let date = try? Date(raw, strategy: .iso8601) {
            return date
        }
        if let date = try? Date(raw, strategy: .iso8601.year().month().day()) {
            return date
        }
        throw AgentToolError(message: "\(name) must be a date like 2026-10-20 or an ISO 8601 date-time.")
    }
}

/// `apply_library_patch`'s input, as the agent sends it.
struct AgentPatchInput: Decodable, Sendable {
    var changes: [AgentPatchChange]
}

struct AgentPatchChange: Decodable, Sendable {
    struct Episode: Decodable, Sendable {
        var season: Int
        var episode: Int
    }

    var op: String
    var mediaRef: Components.Schemas.MediaRef?
    var status: Components.Schemas.LibraryStatus?
    var libraryItemId: String?
    var patch: Components.Schemas.LibraryItemPatch?
    var episodes: [Episode]?
    var season: Int?
    var watched: Bool?
}

/// One library change an agent asked for, validated. Tap-sized changes apply at once; the rest
/// wait for the user (X-009).
enum AgentChange: Sendable {
    case add(MediaRef, LibraryStatus?)
    case update(LibraryItemID, ItemPatch)
    /// Episodes of one show, or (with `season`) every aired episode of a season.
    case episodes(LibraryItemID, keys: [EpisodeKey], season: Int?, watched: Bool)
    case remove(LibraryItemID)

    var itemID: LibraryItemID? {
        switch self {
        case .add: nil
        case let .update(id, _), let .episodes(id, _, _, _), let .remove(id): id
        }
    }

    /// What a single tap could do: one item, at most one episode, and never a removal.
    var isTapSized: Bool {
        switch self {
        case .add, .update: true
        case let .episodes(_, keys, season, _): season == nil && keys.count == 1
        case .remove: false
        }
    }

    static func parse(_ input: AgentPatchInput) throws -> [AgentChange] {
        guard (1 ... AgentTools.maxChanges).contains(input.changes.count) else {
            throw AgentToolError(message: "changes must hold 1 to \(AgentTools.maxChanges) entries.")
        }
        let changes = try input.changes.enumerated().map { index, change in
            try parse(change, at: index)
        }
        var seen = Set<LibraryItemID>()
        for id in changes.compactMap(\.itemID) where !seen.insert(id).inserted {
            throw AgentToolError(message: "Each libraryItemId may appear once; combine its changes.")
        }
        return changes
    }

    private static func parse(_ change: AgentPatchChange, at index: Int) throws -> AgentChange {
        func fail(_ message: String) -> AgentToolError {
            AgentToolError(message: "changes[\(index)]: \(message)")
        }
        func item() throws -> LibraryItemID {
            guard let raw = change.libraryItemId, let id = LibraryItemID(uuidString: raw) else {
                throw fail("needs a valid libraryItemId.")
            }
            return id
        }
        switch change.op {
        case "add":
            guard let ref = change.mediaRef else { throw fail("add needs a mediaRef.") }
            return .add(MediaRef(ref), change.status.map(LibraryStatus.init))
        case "update":
            guard let patch = change.patch else { throw fail("update needs a patch.") }
            return try .update(item(), ItemPatch(patch))
        case "episodes":
            return try episodes(change, item: item(), fail: fail)
        case "remove":
            return try .remove(item())
        default:
            throw fail("op must be add, update, episodes or remove.")
        }
    }

    private static func episodes(
        _ change: AgentPatchChange,
        item id: LibraryItemID,
        fail: (String) -> AgentToolError
    ) throws -> AgentChange {
        guard let watched = change.watched else { throw fail("episodes needs watched: true or false.") }
        if let season = change.season {
            guard change.episodes == nil, watched else {
                throw fail("season marks a whole season watched; pass either season or episodes.")
            }
            return .episodes(id, keys: [], season: season, watched: true)
        }
        guard let episodes = change.episodes, !episodes.isEmpty else {
            throw fail("episodes needs a non-empty episodes list or a season.")
        }
        let keys = try episodes.map { episode in
            do {
                return try EpisodeKey(season: episode.season, episode: episode.episode)
            } catch {
                throw fail("S\(episode.season)E\(episode.episode) is not a valid episode.")
            }
        }
        return .episodes(id, keys: keys, season: nil, watched: watched)
    }
}
