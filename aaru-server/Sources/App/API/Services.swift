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
    var tonight: TonightService
    var stats: StatsService
    var imports: ImportService
    var traktConnect: TraktConnectService
    var malConnect: MALConnectService
    var agentTokens: AgentTokenService
    var scrobble: ScrobbleService
    var listens: ListenService
    var plans: PlanService
    var oauth: OAuthService
    var social: SocialService
    var invites: InviteService
    var groups: GroupService
    var board: BoardService
    var concerts: ConcertService
    var sports: SportsService
    /// Aaru Plus (BIL-001). Purchases answer 503 until `App+build` gives it Apple's verifier.
    var billing: BillingService
    /// Open sockets and browser tickets (GRP-006). One per process.
    var realtime: RealtimeHub
    /// `@aaru` answers; nil when no model is configured (GRP-011).
    var agentReplies: AgentReplyService?
    /// Nil when `VAPID_CONFIG` is unset; the key route then answers 503.
    var webPush: (any WebPushSending)?
    /// Server errors (5xx) to Sentry; nil when `SENTRY_DSN` is unset.
    var sentry: SentryReporter?

    /// `trakt` is nil when Trakt is not configured; connect then answers 503.
    static func make(
        stores: Stores,
        catalogs: CatalogProviders,
        auth: AuthService,
        trakt: TraktAPI? = nil,
        mal: MALAPI? = nil,
        stremio: StremioAccount? = nil,
        catFeed: CATCalendarFeed? = nil,
        publicBaseURL: URL = URL(string: "https://api.aaruapp.com")!,
        // The web app's base URL and the binding cookie's domain, for the OAuth consent page.
        oauth: (webBaseURL: URL, cookieDomain: String?) = (URL(string: "https://aaruapp.com")!, "aaruapp.com"),
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
            discover: discover(stores, catalogs),
            library: library,
            lists: ListService(stores: stores, resolver: resolver, catalog: catalog),
            shelves: ShelfService(stores: stores, library: library),
            schedule: ScheduleService(stores: stores),
            tonight: TonightService(stores: stores),
            stats: StatsService(stores: stores),
            imports: ImportService(
                stores: stores, resolver: resolver,
                trakt: trakt.map { TraktImport(connect: traktConnect(stores, $0), importer: TraktImporter(api: $0)) },
                anilistLists: catalogs.anilist as? any AniListListReading,
                stremio: stremio,
                catFeed: catFeed,
                model: model,
                listenHistory: catalogs.listenHistory
            ),
            traktConnect: traktConnect(stores, trakt),
            malConnect: MALConnectService(stores: stores, settings: mal?.settings, api: mal),
            agentTokens: AgentTokenService(stores: stores, publicBaseURL: publicBaseURL),
            scrobble: ScrobbleService(stores: stores, library: library, resolver: resolver),
            listens: ListenService(stores: stores),
            plans: PlanService(stores: stores, library: library),
            oauth: oauthService(stores, publicBaseURL: publicBaseURL, oauth),
            social: SocialService(stores: stores),
            invites: InviteService(stores: stores, library: library, webBaseURL: oauth.webBaseURL),
            groups: groups,
            board: BoardService(stores: stores, resolver: resolver, library: library),
            concerts: ConcertService(stores: stores, listing: catalogs.concerts, places: catalogs.places),
            sports: SportsService(stores: stores, listing: catalogs.sports),
            billing: BillingService(stores: stores, apple: nil),
            realtime: realtime,
            agentReplies: model.map {
                AgentReplyService(
                    stores: stores, groups: groups, catalog: catalog, resolver: resolver, library: library, model: $0
                )
            }
        )
    }

    private static func discover(_ stores: Stores, _ catalogs: CatalogProviders) -> DiscoverService {
        DiscoverService(
            stores: stores,
            providers: [catalogs.tmdb, catalogs.anilist, catalogs.openLibrary]
                + [catalogs.releases].compactMap(\.self),
            animeFallback: catalogs.tmdb as? any DiscoverListing,
            nextEpisodeTiming: catalogs.airTimes as? any NextEpisodeTiming
        )
    }

    private static func oauthService(
        _ stores: Stores, publicBaseURL: URL, _ oauth: (webBaseURL: URL, cookieDomain: String?)
    ) -> OAuthService {
        OAuthService(
            stores: stores, oauth: stores.oauth,
            settings: .init(
                publicBaseURL: publicBaseURL, webBaseURL: oauth.webBaseURL, cookieDomain: oauth.cookieDomain
            )
        )
    }

    private static func traktConnect(_ stores: Stores, _ api: TraktAPI?) -> TraktConnectService {
        TraktConnectService(stores: stores, settings: api?.settings, api: api)
    }
}
