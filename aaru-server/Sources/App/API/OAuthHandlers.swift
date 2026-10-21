import aaruAPI
import AaruCore
import Foundation
import OpenAPIRuntime

/// OUT-004 · the consent page's side of OAuth: what the app asked, and the user's answer.
/// Session-only, like every `/v1` route; the binding proves it is the browser that asked.
extension APIImplementation {
    func getOAuthRequest(_ input: Operations.GetOAuthRequest.Input) async throws -> Operations.GetOAuthRequest
        .Output
    {
        _ = try currentUser()
        let (request, client) = try await services.oauth.pending(oauthRequestID(input.path.id))
        return .ok(.init(body: .json(.init(
            id: request.id.uuidString.lowercased(),
            clientName: client.name,
            redirectHost: URLComponents(string: request.redirectURI)?.host ?? request.redirectURI,
            kind: .init(rawValue: OAuthService.kind(forClientName: client.name).rawValue) ?? .other,
            expiresAt: request.expiresAt
        ))))
    }

    func approveOAuthRequest(_ input: Operations.ApproveOAuthRequest.Input) async throws
        -> Operations.ApproveOAuthRequest.Output
    {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let next = try await services.oauth.approve(
            oauthRequestID(input.path.id), userID: currentUser(), binding: body.binding, name: body.name,
            allowWrites: body.allowLibraryWrites ?? false
        )
        return .ok(.init(body: .json(.init(redirectTo: next.absoluteString))))
    }

    func denyOAuthRequest(_ input: Operations.DenyOAuthRequest.Input) async throws
        -> Operations.DenyOAuthRequest.Output
    {
        _ = try currentUser()
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let next = try await services.oauth.deny(oauthRequestID(input.path.id), binding: body.binding)
        return .ok(.init(body: .json(.init(redirectTo: next.absoluteString))))
    }

    private func oauthRequestID(_ raw: String) throws -> UUID {
        guard let id = UUID(uuidString: raw) else { throw AppError.notFound("No such connection request.") }
        return id
    }
}
