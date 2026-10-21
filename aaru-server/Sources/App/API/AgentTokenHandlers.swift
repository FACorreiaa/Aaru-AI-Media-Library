import aaruAPI
import AaruCore
import Foundation
import OpenAPIRuntime

extension APIImplementation {
    func listAgentTokens(_ input: Operations.ListAgentTokens.Input) async throws -> Operations.ListAgentTokens.Output {
        let group = AgentTokenKind.Group(rawValue: input.query._for?.rawValue ?? "stremio") ?? .stremio
        let tokens = try await services.agentTokens.tokens(userID: currentUser(), group: group)
        return .ok(.init(body: .json(.init(items: tokens.map(Components.Schemas.AgentToken.init)))))
    }

    func createAgentToken(_ input: Operations.CreateAgentToken.Input) async throws
        -> Operations.CreateAgentToken.Output
    {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let tokens = services.agentTokens
        guard let kind = AgentTokenKind(rawValue: body.kind.rawValue) else { throw AppError.badRequest() }
        // A music token is named for its scrobbler unless the user named it.
        let scrobbler = kind == .music ? MusicScrobbler(body.scrobbler) : nil
        let minted = try await tokens.create(
            userID: currentUser(), kind: kind, name: body.name ?? scrobbler?.title,
            allowLibraryWrites: body.allowLibraryWrites ?? false, allowImports: body.allowImports ?? false
        )
        return .created(.init(body: .json(.init(
            token: .init(minted.token),
            secret: minted.secret,
            stremio: minted.stremio.map { links in
                .init(
                    manifestUrl: links.manifestURL.absoluteString,
                    installUrl: links.installURL.absoluteString,
                    webInstallUrl: links.webInstallURL.absoluteString
                )
            },
            setup: AgentSetup.setup(for: kind, publicBaseURL: tokens.publicBaseURL, secret: minted.secret),
            music: scrobbler.map {
                MusicSetup.setup(for: $0, publicBaseURL: tokens.publicBaseURL, secret: minted.secret)
            }
        ))))
    }

    func getAgentSetup(_ input: Operations.GetAgentSetup.Input) async throws -> Operations.GetAgentSetup.Output {
        _ = try currentUser()
        guard let kind = AgentTokenKind(rawValue: input.path.kind.rawValue),
              let setup = AgentSetup.setup(for: kind, publicBaseURL: services.agentTokens.publicBaseURL)
        else { throw AppError.notFound() }
        return .ok(.init(body: .json(setup)))
    }

    func revokeAgentToken(_ input: Operations.RevokeAgentToken.Input) async throws
        -> Operations.RevokeAgentToken.Output
    {
        guard let id = UUID(uuidString: input.path.id) else { throw AppError.notFound() }
        try await services.agentTokens.revoke(id: id, userID: currentUser())
        return .noContent(.init())
    }
}

extension Components.Schemas.AgentToken {
    init(_ token: AgentToken) {
        self.init(
            id: token.id.uuidString.lowercased(),
            name: token.name,
            kind: .init(rawValue: token.kind.rawValue) ?? .other,
            scopes: token.scopes.map(\.rawValue).sorted().compactMap(ScopesPayloadPayload.init(rawValue:)),
            createdAt: token.createdAt,
            lastUsedAt: token.lastUsedAt
        )
    }
}
