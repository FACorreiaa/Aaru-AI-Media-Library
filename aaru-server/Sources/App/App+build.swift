import Configuration
import FluentPostgresDriver
import Hummingbird
import HummingbirdFluent
import HummingbirdWebSocket
import Logging
import OpenAPIHummingbird
import ServiceLifecycle

// Request context used by application
typealias AppRequestContext = BasicRequestContext
typealias AppWSRequestContext = BasicWebSocketRequestContext

///  Build application
/// - Parameter reader: configuration reader
func buildApplication(reader: ConfigReader) async throws -> some ApplicationProtocol {
    let logger = {
        var logger = Logger(label: "aaru-server")
        logger.logLevel = reader.string(forKey: "log.level", as: Logger.Level.self, default: .info)
        return logger
    }()
    var services: [any Service] = []
    let fluent = Fluent(logger: logger)
    try fluent.databases.use(
        .postgres(
            configuration: .init(
                hostname: reader.string(forKey: "postgres.host", default: "127.0.0.1"),
                port: reader.int(forKey: "postgres.port", default: 5432),
                username: reader.requiredString(forKey: "postgres.user"),
                password: reader.requiredString(forKey: "postgres.password"),
                database: reader.requiredString(forKey: "postgres.database"),
                tls: .disable
            )
        ),
        as: .psql
    )
    // Only run database migration once all migrations have been added
    if reader.bool(forKey: "db.migrate") == true {
        logger.info("Running database migrations")
        try await fluent.migrate()
        exit(0)
    }
    let router = try buildRouter(
        fluent: fluent
    )
    let wsRouter = try buildWebSocketRouter(
        fluent: fluent
    )
    let app = Application(
        router: router,
        server: .http1WebSocketUpgrade(webSocketRouter: wsRouter),
        configuration: ApplicationConfiguration(reader: reader.scoped(to: "http")),
        services: services,
        logger: logger
    )
    return app
}

/// Build router
func buildRouter(
    fluent: Fluent
) throws -> Router<AppRequestContext> {
    let router = Router(context: AppRequestContext.self)
    // Add middleware
    router.addMiddleware {
        // logging middleware
        LogRequestsMiddleware(.info)
        // store request context in TaskLocal
        OpenAPIRequestContextMiddleware()
    }
    // Add OpenAPI handlers
    let api = APIImplementation()
    try api.registerHandlers(on: router)
    return router
}

/// Build websocket router
func buildWebSocketRouter(
    fluent: Fluent
) throws -> Router<AppWSRequestContext> {
    let router = Router(context: AppWSRequestContext.self)
    // Add middleware
    router.addMiddleware {
        // logging middleware
        LogRequestsMiddleware(.info)
    }
    // Add default endpoint
    router.ws("/ws") { request, context in
        return .upgrade()
    } onUpgrade: { inbound, outbound, context in
        // Read inbound message
        for try await message in inbound.messages(maxSize: 1_000_000) {
            // write type and size of message
            switch message {
            case .binary(let buffer):
                try await outbound.write(.text("Binary message, length: \(buffer.readableBytes)"))
            case .text(let string):
                try await outbound.write(.text("Text message, length: \(string.count)"))
            }
        }
    }
    return router
}
