import Foundation

/// One advertised tool and how to run it. Schemas are strict (`additionalProperties: false`)
/// and unknown top-level arguments are rejected server-side too, so a typo is never ignored.
struct MCPTool: Sendable {
    let name: String
    let title: String
    let description: String
    let inputSchema: JSONValue
    /// `false` promises the tool changes nothing the user would notice.
    let writes: Bool
    var destructive = false
    let run: @Sendable (AgentTools, JSONValue, AgentCaller) async throws -> any Encodable & Sendable

    var definition: JSONValue {
        .object([
            "name": .string(name),
            "title": .string(title),
            "description": .string(description),
            "inputSchema": inputSchema,
            "annotations": .object([
                "title": .string(title),
                "readOnlyHint": .bool(!writes),
                "destructiveHint": .bool(destructive),
                "idempotentHint": .bool(!writes),
                "openWorldHint": .bool(false),
            ]),
        ])
    }

    /// The first argument the schema does not name, if any.
    func unknownArgument(in arguments: [String: JSONValue]) -> String? {
        guard let properties = inputSchema.objectValue?["properties"]?.objectValue else { return nil }
        return arguments.keys.sorted().first { properties[$0] == nil }
    }
}

/// AG-001's tools over MCP: exactly the tool layer (`AgentTools`), nothing more.
enum MCPToolCatalog {
    static let all: [MCPTool] = [searchTitles, readLibrary, listAirs, applyLibraryPatch, planImport]

    static func tool(named name: String) -> MCPTool? {
        all.first { $0.name == name }
    }

    static var listing: JSONValue {
        .array(all.map(\.definition))
    }

    static let searchTitles = MCPTool(
        name: "search_titles",
        title: "Search the catalog",
        description: """
        Search movies, shows, anime, books and albums in the public catalog, or read one title's detail \
        (episodes included for shows) by titleId. To add a hit, pass {"type": hit.type, "ids": hit.ids} \
        as the mediaRef of an apply_library_patch add.
        """,
        inputSchema: object([
            "query": string("Words to search for, 1 to 200 characters."),
            "type": enumeration(
                ["all", "movie", "show", "anime", "book", "album"],
                "What to search. all is films, shows and anime together; books only with book, albums only with album."
            ),
            "titleId": string("An Aaru title id, to read that title's detail instead of searching."),
        ]),
        writes: false,
        run: { tools, args, caller in
            try await tools.searchTitles(args.decode(AgentTools.SearchInput.self), caller: caller)
        }
    )

    static let readLibrary = MCPTool(
        name: "read_library",
        title: "Read the library",
        description: """
        The user's library, newest change first: one item by libraryItemId (with watched episodes for \
        shows), or a page filtered by status, type, anime, owned, a list or a pinned shelf. Pass \
        nextCursor back as cursor for the next page.
        """,
        inputSchema: object([
            "libraryItemId": string("One item's id. Other filters are ignored."),
            "status": enumeration(
                ["wishlist", "in_progress", "finished", "dropped"],
                "wishlist is plan to watch, read or listen; in_progress is watching, reading or listening."
            ),
            "type": enumeration(["movie", "show", "book", "album"], "Only this kind of title."),
            "anime": .object(["type": .string("boolean"), "description": .string("Only anime, or no anime.")]),
            "owned": .object(["type": .string("boolean"), "description": .string("Only titles the user owns.")]),
            "listId": string("Only items on this list."),
            "shelfId": string("The items of this saved shelf instead of a filter."),
            "cursor": string("nextCursor from the previous page."),
            "limit": .object([
                "type": .string("integer"), "minimum": .number(1),
                "maximum": .number(Double(AgentTools.maxLibraryPage)), "default": .number(20),
            ]),
        ]),
        writes: false,
        run: { tools, args, caller in
            try await tools.readLibrary(args.decode(AgentTools.LibraryInput.self), caller: caller)
        }
    )

    static let listAirs = MCPTool(
        name: "list_airs",
        title: "What airs and what's next",
        description: """
        calendar: episodes of shows the user tracks airing between from and to (default the next 7 \
        days, at most \(AgentTools.maxAirsDays)). up_next: what to continue, what to start, library \
        counts and unfinished shows, as on the user's Home.
        """,
        inputSchema: object([
            "view": enumeration(["calendar", "up_next"], "Defaults to calendar."),
            "from": string("Start, as 2026-10-20 or an ISO 8601 date-time. Defaults to now."),
            "to": string("End, exclusive. Defaults to 7 days after from."),
        ]),
        writes: false,
        run: { tools, args, caller in
            try await tools.listAirs(args.decode(AgentTools.AirsInput.self), caller: caller)
        }
    )

    static let applyLibraryPatch = MCPTool(
        name: "apply_library_patch",
        title: "Change the library",
        description: """
        Add titles, update status, rating, notes or ownership, tick episodes, or remove items. A \
        single change to one item (at most one episode) applies at once and the user can undo it in \
        Aaru. Anything larger, and any removal, is sent to the user to approve in Aaru and answers \
        applied: false with a planId. Needs a connection the user allowed to make changes.
        """,
        inputSchema: object(
            ["changes": .object([
                "type": .string("array"),
                "minItems": .number(1),
                "maxItems": .number(Double(AgentTools.maxChanges)),
                "items": change,
            ])],
            required: ["changes"]
        ),
        writes: true,
        destructive: true,
        run: { tools, args, caller in
            try await tools.applyLibraryPatch(args.decode(AgentPatchInput.self), caller: caller)
        }
    )

    static let planImport = MCPTool(
        name: "plan_import",
        title: "Hand Aaru a list to import",
        description: """
        Give Aaru a list export (IMDb, Letterboxd, Netflix viewing activity, TV Time or Goodreads CSV, \
        MyAnimeList XML, a Pogdesign CAT iCal file or show list with source cat, or any CSV with title columns) \
        as text. Aaru matches every row and the user reviews and approves the import in Aaru; this tool never \
        changes the library itself. Needs a connection the user allowed imports for.
        """,
        inputSchema: object(
            [
                "text": string("The file's contents, at most 5 MB."),
                "filename": string("The file's name, if it has one. Helps tell formats apart."),
                "source": enumeration(
                    ["auto", "imdb", "letterboxd", "netflix", "tvtime", "goodreads", "mal", "csv", "cat"],
                    "Defaults to auto: detected from the text. A plain list of show names needs cat."
                ),
            ],
            required: ["text"]
        ),
        writes: true,
        run: { tools, args, caller in
            try await tools.planImport(args.decode(AgentTools.ImportInput.self), caller: caller)
        }
    )

    private static let change: JSONValue = .object([
        "type": .string("object"),
        "description": .string("""
        One change. op add needs mediaRef ({type, ids} from a search hit) and may set status; update needs \
        libraryItemId and patch; episodes needs libraryItemId, watched, and episodes or a season (a \
        whole season marks every aired episode watched); remove needs libraryItemId.
        """),
        "required": .array([.string("op")]),
        "additionalProperties": .bool(false),
        "properties": .object([
            "op": enumeration(["add", "update", "episodes", "remove"], nil),
            "mediaRef": .object([
                "type": .string("object"),
                "description": .string("{type, ids} copied from a search hit, or {type, titleId}."),
                "required": .array([.string("type")]),
                "properties": .object([
                    "type": enumeration(["movie", "show", "book", "album"], nil),
                    "ids": .object(["type": .string("object")]),
                    "titleId": string(nil),
                    "title": string(nil),
                    "year": .object(["type": .string("integer")]),
                ]),
            ]),
            "status": enumeration(["wishlist", "in_progress", "finished", "dropped"], nil),
            "libraryItemId": string(nil),
            "patch": .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "status": enumeration(["wishlist", "in_progress", "finished", "dropped"], nil),
                    "rating": .object([
                        "type": .string("number"), "minimum": .number(0.5), "maximum": .number(5),
                        "description": .string("Half steps from 0.5 to 5."),
                    ]),
                    "notes": string(nil),
                    "isOwned": .object(["type": .string("boolean")]),
                    "bookPage": .object(["type": .string("integer"), "minimum": .number(0)]),
                    "bookPercent": .object([
                        "type": .string("number"), "minimum": .number(0), "maximum": .number(100),
                    ]),
                    "clear": .object([
                        "type": .string("array"),
                        "items": enumeration(["rating", "notes", "bookProgress"], nil),
                    ]),
                ]),
            ]),
            "episodes": .object([
                "type": .string("array"),
                "items": object(
                    [
                        "season": .object(["type": .string("integer"), "minimum": .number(0)]),
                        "episode": .object(["type": .string("integer"), "minimum": .number(1)]),
                    ],
                    required: ["season", "episode"]
                ),
            ]),
            "season": .object(["type": .string("integer"), "minimum": .number(0)]),
            "watched": .object(["type": .string("boolean")]),
        ]),
    ])

    // MARK: Schema helpers

    private static func object(_ properties: [String: JSONValue], required: [String] = []) -> JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required.map(JSONValue.string)),
            "additionalProperties": .bool(false),
        ])
    }

    private static func string(_ description: String?) -> JSONValue {
        var schema: [String: JSONValue] = ["type": .string("string")]
        schema["description"] = description.map(JSONValue.string)
        return .object(schema)
    }

    private static func enumeration(_ values: [String], _ description: String?) -> JSONValue {
        var schema: [String: JSONValue] = ["type": .string("string"), "enum": .array(values.map(JSONValue.string))]
        schema["description"] = description.map(JSONValue.string)
        return .object(schema)
    }
}
