import Configuration
import FluentPostgresDriver
import Foundation
import Hummingbird
import HummingbirdFluent
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

    if reader.bool(forKey: "db.migrate") == true {
        let fluent = try await makeFluent(PostgresSettings.load(from: reader), logger: logger)
        logger.info("Running database migrations")
        try await fluent.migrate()
        try await fluent.shutdown()
        exit(0)
    }

    let config = try AppConfig.load(from: reader)
    let fluent = try await makeFluent(config.postgres, logger: logger)
    let stores = try Stores.postgres(fluent.db())
    let transport = AsyncHTTPTransport(client: .shared)
    let auth = makeAuthService(config: config, stores: stores, transport: transport)
    let catalogs = makeCatalogProviders(config: config, transport: transport)
    let services = Services.make(stores: stores, catalogs: catalogs, auth: auth)
    if config.email == nil {
        logger.notice("Email sign-in disabled: RESEND_API_KEY is not set")
    }
    let router = try buildRouter(stores: stores, services: services)
    return Application(
        router: router,
        configuration: ApplicationConfiguration(reader: reader.scoped(to: "http")),
        services: [fluent],
        logger: logger
    )
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
func buildRouter(stores: Stores, services: Services) throws -> Router<AppRequestContext> {
    let router = Router(context: AppRequestContext.self)
    router.addMiddleware {
        LogRequestsMiddleware(.info)
        ErrorMiddleware()
        AuthMiddleware(sessions: stores.sessions)
        // store request context in TaskLocal; must be last
        OpenAPIRequestContextMiddleware()
    }
    try APIImplementation(stores: stores, services: services).registerHandlers(on: router)
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
        }
    )
}

/// One `ProviderClient` (and so one rate pacer) per provider, shared by every caller.
func makeCatalogProviders(config: AppConfig, transport: any HTTPTransport) -> CatalogProviders {
    CatalogProviders(
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
                name: "anilist",
                transport: transport,
                pacer: RequestPacer(requestsPerSecond: 1.5, burst: 5)
            )
        ),
        openLibrary: OpenLibraryCatalog(
            client: ProviderClient(
                name: "openlibrary",
                transport: transport,
                pacer: RequestPacer(requestsPerSecond: 3, burst: 3)
            ),
            userAgent: config.openLibraryUserAgent
        )
    )
}
