import Configuration
import Foundation

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
    /// Bundle ids of the apps (Release and Beta) plus the web Services ID, comma-separated
    /// in `APPLE_AUDIENCES`. Not secret.
    static let defaultAppleAudiences = "com.fernandocorreia.aaru,com.fernandocorreia.aaru.beta"

    var postgres: PostgresSettings
    var tmdbAPIKey: String
    var appleAudiences: Set<String>
    /// The Google OAuth client ids (iOS and web), comma-separated in `GOOGLE_CLIENT_IDS`. Public.
    /// Empty: Google sign-in answers 503.
    var googleAudiences: Set<String>
    /// Nil when `RESEND_API_KEY` is unset: email sign-in answers 503 rather than
    /// blocking boot, because it needs a verified sending domain first.
    var email: EmailSettings?
    /// Sent as Open Library's User-Agent; they ask API users to identify themselves.
    var openLibraryUserAgent: String
    /// Nil when `TRAKT_CLIENT_ID` is unset: Trakt connect answers 503, everything else works.
    var trakt: TraktSettings?
    /// Nil when `APNS_PRIVATE_KEY` is unset: devices still register, no push is sent.
    var push: PushSettings?
    /// `VAPID_CONFIG`: swift-webpush's VAPID configuration JSON. Nil turns web push off. Generate
    /// it once; a new key drops every browser subscription.
    var vapidConfigJSON: String?
    /// Where this API is reachable from outside (`PUBLIC_BASE_URL`), for the Stremio install link.
    var publicBaseURL: URL
    /// Where the web app lives (`WEB_BASE_URL`): the OAuth consent page for Claude's connector.
    var webBaseURL: URL
    /// `OAUTH_COOKIE_DOMAIN`: the parent domain of the API and the web app, so the consent page
    /// can read the cookie the API set. Empty for a host-only cookie (local development).
    var oauthCookieDomain: String?
    /// Browser origins allowed to open the realtime socket (`REALTIME_ORIGINS`, comma-separated).
    var realtimeOrigins: Set<String>
    /// Nil when `ANTHROPIC_API_KEY` is unset: `@aaru` stays off and groups say so (GRP-010).
    var anthropic: AnthropicSettings?

    static let defaultRealtimeOrigins = "https://aaruapp.com,https://www.aaruapp.com,https://beta.aaruapp.com"

    static func load(from reader: ConfigReader) throws -> AppConfig {
        let audiences = reader.string(forKey: "apple.audiences", default: defaultAppleAudiences)
        return try AppConfig(
            postgres: PostgresSettings.load(from: reader),
            tmdbAPIKey: required("tmdb.api.key", env: "TMDB_API_KEY", in: reader),
            appleAudiences: Set(audiences.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }),
            googleAudiences: Set(
                reader.string(forKey: "google.client.ids", default: "").split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            ),
            email: emailSettings(from: reader),
            openLibraryUserAgent: reader.string(
                forKey: "open.library.user.agent",
                default: "Aaru/0.1 (media library; contact: signin@aaruapp.com)"
            ),
            trakt: traktSettings(from: reader),
            push: pushSettings(from: reader),
            vapidConfigJSON: reader.string(forKey: "vapid.config").flatMap { $0.isEmpty ? nil : $0 },
            publicBaseURL: publicBaseURL(from: reader),
            webBaseURL: URL(string: reader.string(forKey: "web.base.url", default: "https://aaruapp.com"))
                ?? URL(string: "https://aaruapp.com")!,
            oauthCookieDomain: reader.string(forKey: "oauth.cookie.domain", default: "aaruapp.com").nilIfBlank,
            realtimeOrigins: Set(
                reader.string(forKey: "realtime.origins", default: defaultRealtimeOrigins).split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            ),
            anthropic: anthropicSettings(from: reader)
        )
    }

    /// The trial's env contract (`platform/infra/docs/llm-haiku-trial.md`): `ANTHROPIC_API_KEY`,
    /// `ANTHROPIC_MODEL`, `ANTHROPIC_EFFORT`; `ANTHROPIC_BASE_URL` only for tests and proxies.
    static func anthropicSettings(from reader: ConfigReader) throws -> AnthropicSettings? {
        guard let key = reader.string(forKey: "anthropic.api.key"), !key.isEmpty else { return nil }
        let base = reader.string(forKey: "anthropic.base.url", default: "https://api.anthropic.com")
        guard let url = URL(string: base), url.scheme == "https" || url.scheme == "http" else {
            throw MissingConfigError(environmentName: "ANTHROPIC_BASE_URL", key: "anthropic.base.url")
        }
        let effort = reader.string(forKey: "anthropic.effort", default: "low")
        return AnthropicSettings(
            apiKey: key, model: reader.string(forKey: "anthropic.model", default: "claude-haiku-5-5"),
            effort: effort.isEmpty ? nil : effort, baseURL: url
        )
    }

    static func publicBaseURL(from reader: ConfigReader) throws -> URL {
        let base = reader.string(forKey: "public.base.url", default: "https://api.aaruapp.com")
        guard let url = URL(string: base), url.scheme == "https" || url.scheme == "http" else {
            throw MissingConfigError(environmentName: "PUBLIC_BASE_URL", key: "public.base.url")
        }
        return url
    }

    private static func pushSettings(from reader: ConfigReader) throws -> PushSettings? {
        guard let key = reader.string(forKey: "apns.private.key"), !key.isEmpty else { return nil }
        return try PushSettings(
            keyID: required("apns.key.id", env: "APNS_KEY_ID", in: reader),
            teamID: reader.string(forKey: "apns.team.id", default: "84X9WYBF36"),
            privateKeyPEM: key
        )
    }

    /// `TRAKT_TOKEN_KEY` (base64, 32 bytes) is required once Trakt is on: tokens are never
    /// stored in clear.
    private static func traktSettings(from reader: ConfigReader) throws -> TraktSettings? {
        guard let clientID = reader.string(forKey: "trakt.client.id"), !clientID.isEmpty else { return nil }
        let redirect = reader.string(
            forKey: "trakt.redirect.uri", default: "https://api.aaruapp.com/v1/imports/trakt/callback"
        )
        guard let redirectURI = URL(string: redirect) else {
            throw MissingConfigError(environmentName: "TRAKT_REDIRECT_URI", key: "trakt.redirect.uri")
        }
        let key = try required("trakt.token.key", env: "TRAKT_TOKEN_KEY", in: reader)
        guard let cipher = try? TokenCipher(base64Key: key) else {
            throw MissingConfigError(environmentName: "TRAKT_TOKEN_KEY (32 bytes, base64)", key: "trakt.token.key")
        }
        let returns = reader.string(
            forKey: "trakt.return.prefixes",
            default: "aaru://,https://aaruapp.com/,https://beta.aaruapp.com/"
        )
        return TraktSettings(
            clientID: clientID,
            redirectURI: redirectURI,
            returnPrefixes: returns.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
            tokenCipher: cipher
        )
    }

    private static func emailSettings(from reader: ConfigReader) throws -> EmailSettings? {
        guard let apiKey = reader.string(forKey: "resend.api.key"), !apiKey.isEmpty else { return nil }
        let base = reader.string(forKey: "magic.link.base.url", default: "https://aaruapp.com/auth/verify")
        guard let linkBaseURL = URL(string: base) else {
            throw MissingConfigError(environmentName: "MAGIC_LINK_BASE_URL", key: "magic.link.base.url")
        }
        return EmailSettings(
            resendAPIKey: apiKey,
            from: reader.string(forKey: "email.from", default: "Aaru <signin@aaruapp.com>"),
            linkBaseURL: linkBaseURL
        )
    }
}

private func required(_ key: String, env: String, in reader: ConfigReader) throws -> String {
    guard let value = reader.string(forKey: ConfigKey(key)), !value.isEmpty else {
        throw MissingConfigError(environmentName: env, key: key)
    }
    return value
}

struct AnthropicSettings: Sendable {
    var apiKey: String
    var model: String
    var effort: String?
    var baseURL: URL
}
