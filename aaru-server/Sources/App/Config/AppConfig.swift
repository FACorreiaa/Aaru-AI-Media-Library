import Configuration

/// A required configuration key is missing. Boot stops and names the key.
struct MissingConfigError: Error, CustomStringConvertible {
    /// The environment variable name, e.g. `TMDB_API_KEY`.
    let environmentName: String
    /// The dotted key `ConfigReader` was asked for, e.g. `tmdb.api.key`.
    let key: String

    var description: String {
        "Missing required configuration \(environmentName) (\(key)). Set it in the environment or in .env."
    }
}

/// Postgres connection settings. Needed both to serve and to migrate.
struct PostgresSettings: Sendable {
    var host: String
    var port: Int
    var user: String
    var password: String
    var database: String

    static func load(from reader: ConfigReader) throws -> PostgresSettings {
        try PostgresSettings(
            host: reader.string(forKey: "postgres.host", default: "127.0.0.1"),
            port: reader.int(forKey: "postgres.port", default: 5432),
            user: required("postgres.user", env: "POSTGRES_USER", in: reader),
            password: required("postgres.password", env: "POSTGRES_PASSWORD", in: reader),
            database: required("postgres.database", env: "POSTGRES_DATABASE", in: reader)
        )
    }
}

/// Settings the server needs to serve requests. Loaded once at boot; a missing
/// required key fails fast with `MissingConfigError` rather than at first use.
///
/// Keys arrive with their owning ticket: Trakt with IMP-002, session signing with
/// AUTH-001. Do not add a key here before the code that reads it exists.
struct AppConfig: Sendable {
    var postgres: PostgresSettings
    var tmdbAPIKey: String

    static func load(from reader: ConfigReader) throws -> AppConfig {
        try AppConfig(
            postgres: PostgresSettings.load(from: reader),
            tmdbAPIKey: required("tmdb.api.key", env: "TMDB_API_KEY", in: reader)
        )
    }
}

private func required(_ key: String, env: String, in reader: ConfigReader) throws -> String {
    guard let value = reader.string(forKey: ConfigKey(key)), !value.isEmpty else {
        throw MissingConfigError(environmentName: env, key: key)
    }
    return value
}
