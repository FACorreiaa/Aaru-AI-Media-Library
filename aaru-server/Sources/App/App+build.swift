import Configuration
import FluentPostgresDriver
import Foundation
import Hummingbird
import HummingbirdFluent
import Logging
import OpenAPIHummingbird
import ServiceLifecycle

/// Request context used by application
typealias AppRequestContext = BasicRequestContext

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
    let router = try buildRouter(stores: stores)
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

/// Builds the router: logging, the shared error shape, then the generated `/v1` handlers.
func buildRouter(stores: Stores) throws -> Router<AppRequestContext> {
    let router = Router(context: AppRequestContext.self)
    router.addMiddleware {
        LogRequestsMiddleware(.info)
        ErrorMiddleware()
        // store request context in TaskLocal; must be last
        OpenAPIRequestContextMiddleware()
    }
    try APIImplementation(stores: stores).registerHandlers(on: router)
    return router
}
