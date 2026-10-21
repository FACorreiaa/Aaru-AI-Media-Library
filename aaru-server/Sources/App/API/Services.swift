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
    var plans: PlanService
    var oauth: OAuthService
    var social: SocialService
    var groups: GroupService
    /// Open sockets and browser tickets (GRP-006). One per process.
    var realtime: RealtimeHub
    /// Nil when `VAPID_CONFIG` is unset; the key route then answers 503.
    var webPush: (any WebPushSending)?

    /// `trakt` is nil when Trakt is not configured; connect then answers 503.
    static func make(
        stores: Stores,
        catalogs: CatalogProviders,
        auth: AuthService,
        trakt: TraktAPI? = nil,
        stremio: StremioAccount? = nil,
        publicBaseURL: URL = URL(string: "https://api.aaruapp.com")!,
        // The web app's base URL and the binding cookie's domain, for the OAuth consent page.
        oauth: (webBaseURL: URL, cookieDomain: String?) = (URL(string: "https://aaruapp.com")!, "aaruapp.com")
    ) -> Services {
        let catalog = CatalogService(stores: stores, catalogs: catalogs)
        let resolver = TitleResolver(stores: stores, catalogs: catalogs)
        let library = LibraryService(stores: stores, resolver: resolver, catalog: catalog)
        let realtime = RealtimeHub()
        return Services(
            auth: auth,
            catalog: catalog,
            discover: DiscoverService(
                stores: stores,
                providers: [catalogs.tmdb, catalogs.anilist, catalogs.openLibrary]
            ),
            library: library,
            lists: ListService(stores: stores, resolver: resolver, catalog: catalog),
            shelves: ShelfService(stores: stores, library: library),
            schedule: ScheduleService(stores: stores, catalog: catalog),
            stats: StatsService(stores: stores),
            imports: ImportService(
                stores: stores, resolver: resolver,
                trakt: trakt.map { TraktImport(connect: traktConnect(stores, $0), importer: TraktImporter(api: $0)) },
                anilistLists: catalogs.anilist as? any AniListListReading,
                stremio: stremio
            ),
            traktConnect: traktConnect(stores, trakt),
            agentTokens: AgentTokenService(stores: stores, publicBaseURL: publicBaseURL),
            scrobble: ScrobbleService(stores: stores, library: library, resolver: resolver),
            plans: PlanService(stores: stores, library: library),
            oauth: OAuthService(
                stores: stores, oauth: stores.oauth,
                settings: .init(
                    publicBaseURL: publicBaseURL, webBaseURL: oauth.webBaseURL, cookieDomain: oauth.cookieDomain
                )
            ),
            social: SocialService(stores: stores),
            groups: GroupService(stores: stores, events: realtime),
            realtime: realtime
        )
    }

    private static func traktConnect(_ stores: Stores, _ api: TraktAPI?) -> TraktConnectService {
        TraktConnectService(stores: stores, settings: api?.settings, api: api)
    }
}
