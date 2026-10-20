import AaruCore
import Foundation

/// The tools `@aaru` may call while answering one mention. All read; none writes.
///
/// Titles reach the model as short refs (`r1`, `r2`, …) handed out by these tools, never as raw
/// ids, so a card can only show a title a tool actually returned.
struct AgentTools {
    let service: AgentReplyService
    let tagger: UserID
    private(set) var refs: [String: MediaRef] = [:]
    /// Titles `show_titles` picked, in order, for the reply's cards.
    private(set) var cards: [Title] = []

    static let definitions: [ModelTool] = [
        ModelTool(
            name: "search_titles",
            description: "Search the catalog for films, shows, anime or books. "
                + "Returns refs to use with the other tools.",
            inputSchema: schema(
                [
                    "query": .object(["type": .string("string")]),
                    "kind": .object([
                        "type": .string("string"),
                        "enum": .array(["movie", "show", "anime", "book"].map(ModelJSON.string)),
                    ]),
                ],
                required: ["query"]
            )
        ),
        ModelTool(
            name: "title_details",
            description: "Facts about one title: year, synopsis, network, and for shows the status and episode count.",
            inputSchema: schema(["ref": .object(["type": .string("string")])], required: ["ref"])
        ),
        ModelTool(
            name: "list_airs",
            description: "The next episodes of a show to air, with dates.",
            inputSchema: schema(["ref": .object(["type": .string("string")])], required: ["ref"])
        ),
        ModelTool(
            name: "read_my_library",
            description: "The library of the person who tagged you (only theirs): titles with status and progress.",
            inputSchema: schema(
                ["status": .object([
                    "type": .string("string"),
                    "enum": .array(["wishlist", "in_progress", "finished", "dropped"].map(ModelJSON.string)),
                ])],
                required: []
            )
        ),
        ModelTool(
            name: "show_titles",
            description: "Attach titles to your reply as cards. Use refs from the other tools.",
            inputSchema: schema(
                ["refs": .object(["type": .string("array"), "items": .object(["type": .string("string")])])],
                required: ["refs"]
            )
        ),
    ]

    private static func schema(_ properties: [String: ModelJSON], required: [String]) -> ModelJSON {
        .object([
            "type": .string("object"), "properties": .object(properties),
            "required": .array(required.map(ModelJSON.string)), "additionalProperties": .bool(false),
        ])
    }

    /// Runs one tool call. A failure becomes an error result the model can read, never a throw.
    mutating func run(_ name: String, input: ModelJSON) async -> (String, Bool) {
        do {
            switch name {
            case "search_titles": return try await (search(input), false)
            case "title_details": return try await (details(input), false)
            case "list_airs": return try await (airs(input), false)
            case "read_my_library": return try await (myLibrary(input), false)
            case "show_titles": return try await (show(input), false)
            default: return ("No tool called \(name).", true)
            }
        } catch {
            return ("That did not work: \(error)", true)
        }
    }

    // MARK: Tools

    private mutating func search(_ input: ModelJSON) async throws -> String {
        guard let query = input["query"]?.string, !query.isEmpty else { return "Give a query." }
        let scopes: [SearchScope] = input["kind"]?.string.flatMap(SearchScope.init(rawValue:)).map { [$0] }
            ?? [.movie, .show]
        var lines: [String] = []
        for scope in scopes {
            for hit in try await service.catalog.search(query: query, scope: scope).hits.prefix(5) {
                let ref = remember(hit.mediaRef)
                let kind = hit.isAnime ? "anime" : hit.type.rawValue
                let year = hit.year.map { " (\($0))" } ?? ""
                let overview = hit.overview.map { " — " + String($0.prefix(160)) } ?? ""
                lines.append("\(ref): \(hit.title)\(year) [\(kind)]\(overview)")
            }
        }
        return lines.isEmpty ? "Nothing found." : lines.joined(separator: "\n")
    }

    private func details(_ input: ModelJSON) async throws -> String {
        let title = try await resolve(input)
        var lines = [AgentReplyService.describe(title)]
        if let network = title.network {
            lines.append("Network: \(network)")
        }
        if let synopsis = title.synopsis {
            lines.append("Synopsis: \(synopsis.prefix(500))")
        }
        if title.type == .show {
            let detail = try await service.catalog.detail(title.id)
            let episodes = detail.episodes ?? []
            let seasons = Set(episodes.map(\.season).filter { $0 > 0 }).count
            lines.append("Status: \(detail.status.map { "\($0)" } ?? "unknown"), \(seasons) seasons, "
                + "\(episodes.count) episodes")
        }
        return lines.joined(separator: "\n")
    }

    private func airs(_ input: ModelJSON) async throws -> String {
        let title = try await resolve(input)
        guard title.type == .show else { return "\(title.title) is not a show." }
        let now = service.now()
        let upcoming = try await (service.catalog.detail(title.id).episodes ?? [])
            .filter { ($0.airsAt ?? .distantPast) > now }
            .sorted { ($0.airsAt ?? now) < ($1.airsAt ?? now) }
            .prefix(5)
        guard !upcoming.isEmpty else { return "No upcoming episodes are known for \(title.title)." }
        let day = ISO8601DateFormatter()
        day.formatOptions = [.withFullDate]
        return upcoming.map { episode in
            "S\(episode.season)E\(episode.episode) \(episode.name ?? ""): \(episode.airsAt.map(day.string) ?? "?")"
        }.joined(separator: "\n")
    }

    /// The tagger's library only: the tool has no way to name anyone else.
    private mutating func myLibrary(_ input: ModelJSON) async throws -> String {
        let status = input["status"]?.string.flatMap(LibraryStatus.init(rawValue:))
        let (entries, _) = try await service.library.list(
            userID: tagger, filter: LibraryFilter(status: status), cursor: nil, limit: 60
        )
        guard !entries.isEmpty else { return "Their library has nothing here." }
        return entries.map { entry in
            let ref = remember(MediaRef(titleID: entry.title.id, type: entry.title.type))
            var line = "\(ref): \(AgentReplyService.describe(entry.title)) — \(entry.item.status.rawValue)"
            if let progress = entry.progress {
                line += ", \(progress.watchedCount)/\(progress.airedCount) episodes"
            }
            if let rating = entry.item.rating {
                line += ", rated \(rating.value)/10"
            }
            return line
        }.joined(separator: "\n")
    }

    private mutating func show(_ input: ModelJSON) async throws -> String {
        guard case let .array(items)? = input["refs"] else { return "Give refs." }
        var shown: [String] = []
        for ref in items.compactMap(\.string) where cards.count < AgentReplyService.maxCards {
            guard let media = refs[ref] else { continue }
            let title = try await service.resolver.resolve(media)
            if !cards.contains(where: { $0.id == title.id }) {
                cards.append(title)
                shown.append(title.title)
            }
        }
        return shown.isEmpty ? "No cards added; use refs the tools gave you." : "Shown: " + shown
            .joined(separator: ", ")
    }

    // MARK: Refs

    private mutating func remember(_ ref: MediaRef) -> String {
        let key = "r\(refs.count + 1)"
        refs[key] = ref
        return key
    }

    private func resolve(_ input: ModelJSON) async throws -> Title {
        guard let key = input["ref"]?.string, let ref = refs[key] else {
            throw AppError.notFound("Unknown ref; use one a tool returned.")
        }
        return try await service.resolver.resolve(ref)
    }
}
