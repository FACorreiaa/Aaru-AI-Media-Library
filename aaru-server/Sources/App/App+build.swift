import Configuration
import FluentPostgresDriver
import FluentSQL
import Foundation
import Hummingbird
import HummingbirdCore
import HummingbirdFluent
import HummingbirdWebSocket
import Logging
import OpenAPIHummingbird
import ServiceLifecycle

/// Builds the application.
///
/// With `db.migrate` set, applies migrations and exits without serving; that path
/// needs only Postgres settings. Serving loads the full `AppConfig` and fails fast,
/// naming the key, when a required value is missing.
func buildApplication(reader: ConfigReader) async throws -> some ApplicationProtocol {
    let logger = {
        var logger = Logger(label: "aaru-server")
        logger.logLevel = reader.string(forKey: "log.level", as: Logger.Level.self, default: .info)
        return logger
    }()

    try await runOneShotModes(reader: reader, logger: logger)

    let config = try AppConfig.load(from: reader)
    let fluent = try await makeFluent(config.postgres, logger: logger)
    let stores = try Stores.postgres(fluent.db())
    let transport = AsyncHTTPTransport(client: .shared)
    let auth = makeAuthService(config: config, stores: stores, transport: transport)
    let catalogs = makeCatalogProviders(config: config, transport: transport)
    let trakt = config.trakt.map { makeTraktAPI($0, transport) }
    let webPush = makeWebPushSender(config.vapidConfigJSON, logger: logger)
    var services = Services.make(
        stores: stores, catalogs: catalogs, auth: auth, trakt: trakt, stremio: makeStremioAccount(transport),
        catFeed: makeCATCalendarFeed(transport),
        publicBaseURL: config.publicBaseURL, oauth: (config.webBaseURL, config.oauthCookieDomain),
        model: makeModelProvider(config.anthropic, transport: transport, logger: logger)
    )
    services.webPush = webPush
    let pushSender = makePushSender(config.push, logger: logger)
    let push = UserPush(stores: stores, sender: pushSender, webPush: webPush)
    services.plans.push = push
    services.groups.push = push
    if config.email == nil {
        logger.notice("Email sign-in disabled: RESEND_API_KEY is not set")
    }
    let router = try buildRouter(stores: stores, services: services, metricsSecret: config.metricsSecret)
    return Application(
        router: router,
        server: realtimeServer(
            RealtimeRoutes(
                hub: services.realtime, groups: services.groups, sessions: stores.sessions,
                allowedOrigins: config.realtimeOrigins
            )
        ),
        configuration: ApplicationConfiguration(reader: reader.scoped(to: "http")),
        // The web push manager finishes in-flight sends on shutdown.
        services: backgroundServices(
            fluent: fluent, stores: stores, services: services,
            airing: AiringNotifier(stores: stores, sender: pushSender, webPush: webPush),
            logger: logger
        ) + [webPush?.manager].compactMap(\.self),
        logger: logger
    )
}

/// Everything that runs beside the HTTP server: the database, and the workers.
func backgroundServices(
    fluent: Fluent, stores: Stores, services: Services, airing: AiringNotifier, logger: Logger
) -> [any Service] {
    [
        fluent,
        ImportWorker(imports: services.imports, logger: logger),
        AiringNotifierService(notifier: airing, logger: logger),
        CatalogRefreshService(
            refresher: CatalogRefresher(stores: stores, catalog: services.catalog),
            logger: logger
        ),
        ConcertRefreshService(
            refresher: ConcertRefresher(
                stores: stores,
                artists: services.catalog.catalogs.music as? any AlbumArtistListing,
                listing: services.concerts.listing
            ),
            logger: logger
        ),
    ] + (services.agentReplies.map { [AgentReplyWorker(replies: $0, logger: logger)] } ?? [])
        + (services.catalog.catalogs.recordings.map {
            [ListenResolverService(resolver: ListenResolver(stores: stores, recordings: $0), logger: logger)]
        } ?? [])
}

/// HTTP/1 with the `/v1/ws` upgrade (GRP-006). A ping every 25 s keeps a proxy with a 60 s idle
/// timeout from closing a quiet socket.
func realtimeServer(_ realtime: RealtimeRoutes) -> HTTPServerBuilder {
    .http1WebSocketUpgrade(
        webSocketRouter: realtime.router(),
        configuration: .init(ws: .init(autoPing: .enabled(timePeriod: .seconds(25))))
    )
}

/// `db.migrate` and `anime.mappings` do their one job and exit without serving; both need only
/// Postgres settings.
func runOneShotModes(reader: ConfigReader, logger: Logger) async throws {
    if reader.bool(forKey: "db.migrate") == true {
        let fluent = try await makeFluent(PostgresSettings.load(from: reader), logger: logger)
        try await waitForDatabase(fluent, logger: logger)
        logger.info("Running database migrations")
        try await fluent.migrate()
        try await fluent.shutdown()
        exit(0)
    }
    if let source = reader.string(forKey: "anime.mappings") {
        try await loadAnimeMappings(from: source, reader: reader, logger: logger)
        exit(0)
    }
}

/// CAT-010 · `aaru --anime-mappings <path|url|default>` loads Fribb's anime list into
/// `anime_mappings` and exits. Needs only Postgres settings, like `db.migrate`.
func loadAnimeMappings(from source: String, reader: ConfigReader, logger: Logger) async throws {
    let fluent = try await makeFluent(PostgresSettings.load(from: reader), logger: logger)
    do {
        try await waitForDatabase(fluent, logger: logger)
        let resolved = source == "default" || source.isEmpty ? AnimeMappingLoader.defaultSource : source
        var transport = AsyncHTTPTransport(client: .shared)
        transport.maxBodyBytes = 64 * 1024 * 1024
        let mappings = try await AnimeMappingLoader.parse(AnimeMappingLoader.load(from: resolved, transport: transport))
        try await Stores.postgres(fluent.db()).animeMappings.upsertMany(mappings)
        logger.info("Anime mappings loaded", metadata: [
            "count": "\(mappings.count)", "withTMDB": "\(mappings.count { $0.tmdb != nil })",
        ])
        try await fluent.shutdown()
    } catch {
        try? await fluent.shutdown()
        throw error
    }
}

/// The Trakt client, or nil when Trakt is not configured.
func makeTraktAPI(_ settings: TraktSettings?, transport: any HTTPTransport) -> TraktAPI? {
    settings.map { settings in
        // Trakt allows 1000 calls per 5 minutes per user; stay well under it.
        TraktAPI(
            client: ProviderClient(
                name: "trakt", transport: transport, pacer: RequestPacer(requestsPerSecond: 2, burst: 10)
            ),
            settings: settings
        )
    }
}

/// The agent's model, or nil (with a notice) when no key is configured: `@aaru` then stays off.
func makeModelProvider(
    _ settings: AnthropicSettings?, transport: any HTTPTransport, logger: Logger
) -> (any ModelProviding)? {
    guard let settings else {
        logger.notice("@aaru disabled: ANTHROPIC_API_KEY is not set")
        return nil
    }
    return AnthropicMessagesProvider(
        transport: transport, apiKey: settings.apiKey, model: settings.model, baseURL: settings.baseURL,
        effort: settings.effort, workspaceID: settings.workspaceID
    )
}

/// A fresh pod can be refused by Postgres for its first seconds while the network policy that
/// admits it is still being programmed. One-shot modes start talking to the database at once,
/// so they wait here (up to `attempts` × `delay`) instead of crashing on the first refusal.
func waitForDatabase(
    _ fluent: Fluent,
    attempts: Int = 10,
    delay: Duration = .seconds(3),
    logger: Logger
) async throws {
    guard let sql = fluent.db() as? any SQLDatabase else { throw MigrationNeedsSQL() }
    for attempt in 1 ... attempts {
        do {
            try await sql.raw("SELECT 1").run()
            return
        } catch where attempt < attempts {
            logger.notice("Database not reachable yet, retrying", metadata: ["attempt": "\(attempt)"])
            try await Task.sleep(for: delay)
        }
    }
}

/// The APNs sender, or nil (with a notice) when no key is configured or the key does not parse.
func makePushSender(_ settings: PushSettings?, logger: Logger) -> (any PushSending)? {
    guard let settings else {
        logger.notice("Push disabled: APNS_PRIVATE_KEY is not set")
        return nil
    }
    do {
        return try APNSPushSender(settings: settings)
    } catch {
        logger.error("Push disabled: APNS_PRIVATE_KEY is not a valid .p8 key")
        return nil
    }
}

/// The web push sender, or nil (with a notice) when `VAPID_CONFIG` is unset or does not parse.
func makeWebPushSender(_ json: String?, logger: Logger) -> WebPushSender? {
    guard let json else {
        logger.notice("Web push disabled: VAPID_CONFIG is not set")
        return nil
    }
    do {
        return try WebPushSender(configurationJSON: json, logger: logger)
    } catch {
        logger.error("Web push disabled: VAPID_CONFIG is not a valid VAPID configuration")
        return nil
    }
}

/// A Fluent instance on Postgres with every migration registered.
func makeFluent(_ settings: PostgresSettings, logger: Logger) async throws -> Fluent {
    let fluent = Fluent(logger: logger)
    fluent.databases.use(
        .postgres(
            configuration: .init(
                hostname: settings.host,
                port: settings.port,
                username: settings.user,
                password: settings.password,
                database: settings.database,
                tls: .disable
            )
        ),
        as: .psql
    )
    await fluent.migrations.add(allMigrations)
    return fluent
}

/// Builds the router: logging, the shared error shape, auth, then the generated `/v1` handlers.
func buildRouter(stores: Stores, services: Services, metricsSecret: String = "") throws -> Router<AppRequestContext> {
    let router = Router(context: AppRequestContext.self)
    router.addMiddleware {
        RedactedLogRequestsMiddleware(.info)
        ErrorMiddleware()
        AuthMiddleware(sessions: stores.sessions)
        // store request context in TaskLocal; must be last
        OpenAPIRequestContextMiddleware()
    }
    try APIImplementation(stores: stores, services: services).registerHandlers(
        on: router, configuration: .init(dateTranscoder: LenientDateTranscoder())
    )
    // Trakt's browser redirect (IMP-002). Plain, not generated: the generated server would
    // percent-encode the `aaru://` Location.
    router.get("/v1/imports/trakt/callback") { request, _ -> Response in
        let query = request.uri.queryParameters
        let next = try await services.traktConnect.callback(
            code: query["code"].map(String.init), state: query["state"].map(String.init),
            error: query["error"].map(String.init)
        )
        return Response(status: .found, headers: [.location: next.absoluteString])
    }
    StremioRoutes(
        service: StremioService(
            library: services.library, schedule: services.schedule, catalog: services.catalog,
            scrobble: services.scrobble
        ),
        tokens: services.agentTokens
    ).register(on: router)
    MCPRoutes(tools: AgentTools(services: services, stores: stores), tokens: services.agentTokens).register(on: router)
    ScrobbleRoutes(scrobble: services.scrobble, tokens: services.agentTokens).register(on: router)
    ListenBrainzRoutes(listens: services.listens, tokens: services.agentTokens).register(on: router)
    OAuthRoutes(service: services.oauth).register(on: router)
    InternalMetricsRoutes(users: stores.users, secret: metricsSecret).register(on: router)
    return router
}

func makeAuthService(config: AppConfig, stores: Stores, transport: any HTTPTransport) -> AuthService {
    AuthService(
        stores: stores,
        apple: AppleIdentityVerifier(
            audiences: config.appleAudiences,
            jwks: AppleJWKSCache(transport: transport, url: AppleIdentityVerifier.keysURL)
        ),
        magicLinks: config.email.map { email in
            (
                ResendMagicLinkSender(transport: transport, apiKey: email.resendAPIKey, from: email.from),
                email.linkBaseURL
            )
        },
        google: config.googleAudiences.isEmpty ? nil : GoogleIdentityVerifier(
            audiences: config.googleAudiences,
            jwks: AppleJWKSCache(transport: transport, url: GoogleIdentityVerifier.keysURL)
        )
    )
}

/// Trakt allows 500 reads per 5 minutes per user (1.67/s); stay under it.
func makeTraktAPI(_ settings: TraktSettings, _ transport: any HTTPTransport) -> TraktAPI {
    TraktAPI(
        client: ProviderClient(
            name: "trakt", transport: transport, pacer: RequestPacer(requestsPerSecond: 1.5, burst: 10)
        ),
        settings: settings
    )
}

/// Stremio's account API (a few calls per import) and Cinemeta (one call per show in a library).
func makeStremioAccount(_ transport: any HTTPTransport) -> StremioAccount {
    func client(_ name: String, perSecond: Double) -> ProviderClient {
        ProviderClient(name: name, transport: transport, pacer: RequestPacer(requestsPerSecond: perSecond, burst: 5))
    }
    return StremioAccount(
        link: client("stremio-link", perSecond: 2),
        api: client("stremio", perSecond: 2),
        cinemeta: client("cinemeta", perSecond: 5)
    )
}

/// The user's own CAT calendar link (IMP-010): one request per import, so a slow pacer.
func makeCATCalendarFeed(_ transport: any HTTPTransport) -> CATCalendarFeed {
    CATCalendarFeed(client: ProviderClient(
        name: "pogdesign", transport: transport, pacer: RequestPacer(requestsPerSecond: 1, burst: 3)
    ))
}

/// One `ProviderClient` (and so one rate pacer) per provider, shared by every caller.
func makeCatalogProviders(config: AppConfig, transport: any HTTPTransport) -> CatalogProviders {
    let musicBrainz = makeMusicBrainz(userAgent: config.openLibraryUserAgent, transport)
    return CatalogProviders(
        tmdb: TMDBCatalog(
            client: ProviderClient(
                name: "tmdb",
                transport: transport,
                pacer: RequestPacer(requestsPerSecond: 40, burst: 40)
            ),
            apiKey: config.tmdbAPIKey
        ),
        anilist: AniListCatalog(
            // 90 requests/minute.
            client: ProviderClient(
                name: "anilist", transport: transport, pacer: RequestPacer(requestsPerSecond: 1.5, burst: 5),
                classify: AniListCatalog.classify
            ),
            userAgent: config.openLibraryUserAgent
        ),
        openLibrary: OpenLibraryCatalog(
            client: ProviderClient(
                name: "openlibrary",
                transport: transport,
                pacer: RequestPacer(requestsPerSecond: 3, burst: 3)
            ),
            userAgent: config.openLibraryUserAgent
        ),
        airTimes: TVmazeAirTimes(
            // TVmaze allows ~20 calls per 10 seconds per IP.
            client: ProviderClient(
                name: "tvmaze",
                transport: transport,
                pacer: RequestPacer(requestsPerSecond: 1.8, burst: 5)
            )
        ),
        music: musicBrainz,
        releases: ListenBrainzReleases(
            client: ProviderClient(
                name: "listenbrainz",
                transport: transport,
                pacer: RequestPacer(requestsPerSecond: 1, burst: 2)
            ),
            userAgent: config.openLibraryUserAgent
        ),
        recordings: musicBrainz,
        concerts: config.concertsAPIKey.map { makeConcertListing(apiKey: $0, transport) },
        places: makePlaceSearch(transport)
    )
}

/// MusicBrainz allows one request a second per client: album search, listen lookups (MUS-006) and
/// concert artists (MUS-003) share this one.
func makeMusicBrainz(userAgent: String, _ transport: any HTTPTransport) -> MusicBrainzCatalog {
    MusicBrainzCatalog(
        client: ProviderClient(
            name: "musicbrainz", transport: transport, pacer: RequestPacer(requestsPerSecond: 1, burst: 1)
        ),
        userAgent: userAgent
    )
}
