import Foundation

/// Business services the handlers call. Built once at boot; tests build them over fakes.
struct Services: Sendable {
    var auth: AuthService
    var catalog: CatalogService
    var discover: DiscoverService
    var library: LibraryService
    var lists: ListService
    var shelves: ShelfService
    var schedule: ScheduleService
    var stats: StatsService
    var imports: ImportService
    var traktConnect: TraktConnectService
    var agentTokens: AgentTokenService
    var scrobble: ScrobbleService
    var social: SocialService
    var groups: GroupService
    /// Open sockets and browser tickets (GRP-006). One per process.
    var realtime: RealtimeHub
    /// `@aaru` answers; nil when no model is configured (GRP-011).
    var agentReplies: AgentReplyService?

    /// `trakt` is nil when Trakt is not configured; connect then answers 503.
    static func make(
        stores: Stores,
        catalogs: CatalogProviders,
        auth: AuthService,
        trakt: TraktAPI? = nil,
        publicBaseURL: URL = URL(string: "https://api.aaruapp.com")!,
        model: (any ModelProviding)? = nil
    ) -> Services {
        let catalog = CatalogService(stores: stores, catalogs: catalogs)
        let resolver = TitleResolver(stores: stores, catalogs: catalogs)
        let library = LibraryService(stores: stores, resolver: resolver, catalog: catalog)
        let realtime = RealtimeHub()
        let groups = GroupService(
            stores: stores, events: realtime, resolver: resolver, library: library, agentAvailable: model != nil
        )
        return Services(
            auth: auth,
            catalog: catalog,
            discover: DiscoverService(
                stores: stores,
                providers: [catalogs.tmdb, catalogs.anilist, catalogs.openLibrary]
            ),
            library: library,
            lists: ListService(stores: stores, resolver: resolver),
            shelves: ShelfService(stores: stores, library: library),
            schedule: ScheduleService(stores: stores, catalog: catalog),
            stats: StatsService(stores: stores),
            imports: ImportService(
                stores: stores, resolver: resolver,
                trakt: trakt.map { TraktImport(connect: traktConnect(stores, $0), importer: TraktImporter(api: $0)) },
                anilistLists: catalogs.anilist as? any AniListListReading
            ),
            traktConnect: traktConnect(stores, trakt),
            agentTokens: AgentTokenService(stores: stores, publicBaseURL: publicBaseURL),
            scrobble: ScrobbleService(stores: stores, library: library, resolver: resolver),
            social: SocialService(stores: stores),
            groups: groups,
            realtime: realtime,
            agentReplies: model.map {
                AgentReplyService(
                    stores: stores, groups: groups, catalog: catalog, resolver: resolver, library: library, model: $0
                )
            }
        )
    }

    private static func traktConnect(_ stores: Stores, _ api: TraktAPI?) -> TraktConnectService {
        TraktConnectService(stores: stores, settings: api?.settings, api: api)
    }
}
