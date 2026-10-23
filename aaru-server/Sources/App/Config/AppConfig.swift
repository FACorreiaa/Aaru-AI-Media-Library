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
    /// `POSTGRES_POOL_SIZE`: connections this process may open. Every store shares the pool of one
    /// event loop (`Stores.postgres(fluent.db())`), so this is the process total, not per loop.
    /// Fluent's default of one made every request and worker queue on a single connection.
    var poolSize: Int = 10
    /// `POSTGRES_POOL_TIMEOUT`: seconds a query waits for a free connection before it fails.
    var poolTimeoutSeconds: Int = 10

    static func load(from reader: ConfigReader) throws -> PostgresSettings {
        try PostgresSettings(
            host: reader.string(forKey: "postgres.host", default: "127.0.0.1"),
            port: reader.int(forKey: "postgres.port", default: 5432),
            user: required("postgres.user", env: "POSTGRES_USER", in: reader),
            password: required("postgres.password", env: "POSTGRES_PASSWORD", in: reader),
            database: required("postgres.database", env: "POSTGRES_DATABASE", in: reader),
            poolSize: max(1, reader.int(forKey: "postgres.pool.size", default: 10)),
            poolTimeoutSeconds: max(1, reader.int(forKey: "postgres.pool.timeout", default: 10))
        )
    }
}

/// How many jobs each queue runs at once in this process. Both queues lease with `SKIP LOCKED`,
/// so workers (and replicas) never take the same job.
struct WorkerSettings: Sendable {
    /// `IMPORTS_WORKERS`: imports matched at once. Each holds a few connections while it matches.
    var imports: Int = 1
    /// `AGENT_REPLY_WORKERS`: `@aaru` mentions answered at once.
    var agentReplies: Int = 1

    static func load(from reader: ConfigReader) -> WorkerSettings {
        WorkerSettings(
            imports: min(8, max(1, reader.int(forKey: "imports.workers", default: 1))),
            agentReplies: min(8, max(1, reader.int(forKey: "agent.reply.workers", default: 1)))
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
    /// The contact string catalog providers that ask for one get (Open Library, AniList).
    static let defaultProviderUserAgent = "Aaru/0.1 (media library; contact: signin@aaruapp.com)"

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
    /// Nil when `TICKETMASTER_API_KEY` is unset: concerts answer `unavailable` (MUS-003).
    var concertsAPIKey: String?
    /// `METRICS_SECRET`: the bearer facorreia.com/apps sends to `/internal/metrics`. Empty turns
    /// the route off.
    var metricsSecret: String
    /// `METRICS_PORT`: where `GET /metrics` (Prometheus) listens, apart from the API port so the
    /// Ingress never routes to it. 0 turns it off.
    var metricsPort: Int
    /// Nil when `SENTRY_DSN` is unset: server errors are logged only.
    var sentry: SentrySettings?
    /// Nil when `POSTHOG_PROJECT_TOKEN` is unset: no product events are sent.
    var posthog: PostHogSettings?
    /// Jobs per queue at once (`IMPORTS_WORKERS`, `AGENT_REPLY_WORKERS`).
    var workers: WorkerSettings

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
                default: defaultProviderUserAgent
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
            anthropic: anthropicSettings(from: reader),
            concertsAPIKey: reader.string(forKey: "ticketmaster.api.key").flatMap(\.nilIfBlank),
            metricsSecret: reader.string(forKey: "metrics.secret", default: ""),
            metricsPort: reader.int(forKey: "metrics.port", default: 9090),
            sentry: reader.string(forKey: "sentry.dsn").flatMap(\.nilIfBlank).map {
                SentrySettings(
                    dsn: $0,
                    environment: reader.string(forKey: "sentry.environment", default: "production"),
                    release: reader.string(forKey: "aaru.release").flatMap(\.nilIfBlank)
                )
            },
            posthog: postHogSettings(from: reader),
            workers: WorkerSettings.load(from: reader)
        )
    }

    /// `POSTHOG_PROJECT_TOKEN` (public: it can only write events) and `POSTHOG_HOST`, PostHog's EU
    /// cloud unless set.
    static func postHogSettings(from reader: ConfigReader) throws -> PostHogSettings? {
        guard let token = reader.string(forKey: "posthog.project.token")?.nilIfBlank else { return nil }
        let host = reader.string(forKey: "posthog.host", default: "https://eu.i.posthog.com")
        guard let url = URL(string: host), url.scheme == "https" || url.scheme == "http" else {
            throw MissingConfigError(environmentName: "POSTHOG_HOST", key: "posthog.host")
        }
        return PostHogSettings(projectToken: token, host: url)
    }

    /// The trial's env contract (`platform/infra/docs/llm-haiku-trial.md`): `ANTHROPIC_API_KEY`,
    /// `ANTHROPIC_MODEL`, `ANTHROPIC_EFFORT`; `ANTHROPIC_WORKSPACE_ID` when the key is not scoped
    /// to a workspace; `ANTHROPIC_BASE_URL` only for tests and proxies.
    static func anthropicSettings(from reader: ConfigReader) throws -> AnthropicSettings? {
        guard let key = reader.string(forKey: "anthropic.api.key"), !key.isEmpty else { return nil }
        let base = reader.string(forKey: "anthropic.base.url", default: "https://api.anthropic.com")
        guard let url = URL(string: base), url.scheme == "https" || url.scheme == "http" else {
            throw MissingConfigError(environmentName: "ANTHROPIC_BASE_URL", key: "anthropic.base.url")
        }
        let effort = reader.string(forKey: "anthropic.effort", default: "low")
        let workspace = reader.string(forKey: "anthropic.workspace.id", default: "")
        // Claude Haiku 5.5's list price; set both when ANTHROPIC_MODEL names another model.
        let pricing = ModelPricing(
            inputPerMTok: Double(reader.string(forKey: "anthropic.price.input", default: "0.10")) ?? 0.10,
            outputPerMTok: Double(reader.string(forKey: "anthropic.price.output", default: "0.50")) ?? 0.50
        )
        return AnthropicSettings(
            apiKey: key, model: reader.string(forKey: "anthropic.model", default: "claude-haiku-5-5"),
            effort: effort.isEmpty ? nil : effort, baseURL: url, workspaceID: workspace.isEmpty ? nil : workspace,
            pricing: pricing
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

struct SentrySettings: Sendable {
    var dsn: String
    /// `SENTRY_ENVIRONMENT`, `production` unless set.
    var environment: String
    /// `AARU_RELEASE`: the commit the image was built from (a Docker build arg).
    var release: String?
}

struct PostHogSettings: Sendable {
    var projectToken: String
    var host: URL
}

struct AnthropicSettings: Sendable {
    var apiKey: String
    var model: String
    var effort: String?
    var baseURL: URL
    var workspaceID: String?
    /// `ANTHROPIC_PRICE_INPUT` / `ANTHROPIC_PRICE_OUTPUT`, dollars per million tokens.
    var pricing = ModelPricing(inputPerMTok: 0.10, outputPerMTok: 0.50)
}
