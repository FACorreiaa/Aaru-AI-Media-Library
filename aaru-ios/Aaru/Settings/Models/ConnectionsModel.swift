import AaruAPI
import Foundation
import Observation

typealias AgentToken = Components.Schemas.AgentToken
typealias AgentTokenCreated = Components.Schemas.AgentTokenCreated

/// Settings → Connections (UX-023): everything that reaches Aaru with a token of its own:
/// agents over MCP and the browser extension, the Stremio addon, and music scrobblers
/// (GET/POST/DELETE /v1/agent/tokens), and MyAnimeList (SCR-005, /v1/connections/mal). One verb
/// ends any of them: Disconnect (UX-024).
@MainActor
@Observable
final class ConnectionsModel {
    enum Group: CaseIterable {
        case agents, stremio, music
    }

    private(set) var agents: [AgentToken] = []
    private(set) var stremio: [AgentToken] = []
    private(set) var scrobblers: [AgentToken] = []
    /// The newest listen, shown under Music as the way to Listens once there is one.
    private(set) var latestListen: Components.Schemas.Listen?
    /// MyAnimeList: nil until the connection is read, or when the server has it off.
    private(set) var mal: Components.Schemas.MALConnection?
    private(set) var malBusy = false
    private(set) var hasLoaded = false
    var problem: String?

    /// Where MyAnimeList's sign-in sheet returns.
    static let malReturn = "aaru://settings/myanimelist"

    @ObservationIgnored private let api: Client?

    init(api: Client?) {
        self.api = api
    }

    var isAvailable: Bool {
        api != nil
    }

    func load() async {
        guard let api else { return }
        defer { hasLoaded = true }
        do {
            async let mcp = api.listAgentTokens(query: .init(_for: .mcp))
            async let scrobble = api.listAgentTokens(query: .init(_for: .scrobble))
            async let addon = api.listAgentTokens(query: .init(_for: .stremio))
            async let music = api.listAgentTokens(query: .init(_for: .music))
            let live = try await Self.items(mcp) + Self.items(scrobble)
            let addons = try await Self.items(addon)
            let players = try await Self.items(music)
            agents = live.sorted { $0.createdAt > $1.createdAt }
            stremio = addons.filter { $0.kind == .stremio }
            scrobblers = players.filter { $0.kind == .music }
        } catch let failure as Failure {
            problem = failure.message ?? "Your connections could not be loaded."
        } catch {
            problem = "Your connections could not be loaded. Aaru could not reach the server."
        }
        // The last listen is a nicety; nothing is reported when it fails.
        latestListen = await latestListenNow()
        await loadMAL()
    }

    /// Mints a token. The answer holds the secret, shown once by the caller.
    func create(_ body: Components.Schemas.AgentTokenCreate) async -> Result<AgentTokenCreated, Failure> {
        guard let api else { return .failure(Failure("This build has no server configured.")) }
        do {
            switch try await api.createAgentToken(body: .json(body)) {
            case let .created(response):
                let result = try response.body.json
                insert(result.token)
                return .success(result)
            case let .default(_, error):
                return .failure(Failure((try? error.body.json.message) ?? "The connection could not be made."))
            }
        } catch {
            return .failure(Failure("The connection could not be made. Aaru could not reach the server."))
        }
    }

    /// Ends a connection at once.
    func disconnect(_ token: AgentToken) async {
        guard let api else { return }
        problem = nil
        do {
            switch try await api.revokeAgentToken(path: .init(id: token.id)) {
            case .noContent:
                agents.removeAll { $0.id == token.id }
                stremio.removeAll { $0.id == token.id }
                scrobblers.removeAll { $0.id == token.id }
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "\(token.name) was not disconnected."
            }
        } catch {
            problem = "\(token.name) was not disconnected. Aaru could not reach the server."
        }
    }

    /// An agent's setup steps before a token exists (GET /v1/agent/setup/{kind}). A convenience:
    /// nil when they cannot be read, and connecting still works.
    func setup(for kind: Components.Schemas.AgentMCPKind) async -> Components.Schemas.AgentSetup? {
        guard let api, case let .ok(response) = try? await api.getAgentSetup(path: .init(kind: kind)) else {
            return nil
        }
        return try? response.body.json
    }

    /// The newest listen, or nil before the first one or when it could not be read.
    func latestListenNow() async -> Components.Schemas.Listen? {
        guard let api, case let .ok(response) = try? await api.listListens(query: .init(limit: 1)) else {
            return nil
        }
        return try? response.body.json.items.first
    }

    func reset() {
        agents = []
        stremio = []
        scrobblers = []
        latestListen = nil
        mal = nil
        hasLoaded = false
        problem = nil
    }

    // MARK: MyAnimeList (SCR-005)

    func loadMAL() async {
        guard let api else { return }
        if case let .ok(response) = try? await api.getMALConnection() {
            mal = try? response.body.json
        }
    }

    /// MyAnimeList's sign-in page for this user. The server holds the PKCE verifier.
    func malAuthorizeURL() async -> URL? {
        guard let api else { return nil }
        malBusy = true
        problem = nil
        defer { malBusy = false }
        do {
            if case let .ok(response) = try await api.connectMAL(body: .json(.init(returnTo: Self.malReturn))),
               let page = try URL(string: response.body.json.authorizeUrl)
            {
                return page
            }
            problem = "MyAnimeList is not available right now. Try again later."
        } catch {
            problem = "MyAnimeList could not be reached. Aaru could not reach the server."
        }
        return nil
    }

    /// MyAnimeList's sign-in sheet came back to `aaru://…?mal=`.
    func finishMAL(_ callback: URL) async {
        let result = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "mal" }?.value
        switch result {
        case "connected": await loadMAL()
        case "denied": break
        default: problem = "MyAnimeList could not finish connecting. Try again."
        }
    }

    func disconnectMAL() async {
        guard let api else { return }
        malBusy = true
        problem = nil
        defer { malBusy = false }
        do {
            switch try await api.disconnectMAL() {
            case .noContent:
                mal = .init(connected: false, needsReconnect: false)
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "MyAnimeList was not disconnected. Try again."
            }
        } catch {
            problem = "MyAnimeList was not disconnected. Aaru could not reach the server."
        }
    }

    private func insert(_ token: AgentToken) {
        switch token.kind {
        case .stremio: stremio.insert(token, at: 0)
        case .music: scrobblers.insert(token, at: 0)
        default: agents.insert(token, at: 0)
        }
    }

    private static func items(_ output: Operations.ListAgentTokens.Output) throws -> [AgentToken] {
        switch output {
        case let .ok(response): return try response.body.json.items
        case let .default(_, error): throw Failure(try? error.body.json.message)
        }
    }

    struct Failure: Error {
        let message: String?

        init(_ message: String?) {
            self.message = message
        }
    }
}
