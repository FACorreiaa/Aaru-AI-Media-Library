import aaruAPI
import AaruCore
import Foundation
import OpenAPIRuntime

extension APIImplementation {
    func listAgentTokens(_: Operations.ListAgentTokens.Input) async throws -> Operations.ListAgentTokens.Output {
        let tokens = try await services.agentTokens.tokens(userID: currentUser())
        return .ok(.init(body: .json(.init(items: tokens.map(Components.Schemas.AgentToken.init)))))
    }

    func createAgentToken(_ input: Operations.CreateAgentToken.Input) async throws
        -> Operations.CreateAgentToken.Output
    {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let minted = try await services.agentTokens.create(
            userID: currentUser(), kind: .stremio, name: body.name,
            allowLibraryWrites: body.allowLibraryWrites ?? false
        )
        return .created(.init(body: .json(.init(
            token: .init(minted.token),
            secret: minted.secret,
            stremio: .init(
                manifestUrl: minted.manifestURL.absoluteString,
                installUrl: minted.installURL.absoluteString,
                webInstallUrl: minted.webInstallURL.absoluteString
            )
        ))))
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
            kind: .stremio,
            scopes: token.scopes.map(\.rawValue).sorted().compactMap(ScopesPayloadPayload.init(rawValue:)),
            createdAt: token.createdAt,
            lastUsedAt: token.lastUsedAt
        )
    }
}
