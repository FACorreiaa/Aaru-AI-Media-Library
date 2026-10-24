import aaruAPI
import Foundation

/// MyAnimeList connect (SCR-005).
extension APIImplementation {
    func connectMAL(_ input: Operations.ConnectMAL.Input) async throws -> Operations.ConnectMAL.Output {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let url = try await services.malConnect.start(userID: currentUser(), returnTo: body.returnTo)
        return .ok(.init(body: .json(.init(authorizeUrl: url.absoluteString))))
    }

    func getMALConnection(_: Operations.GetMALConnection.Input) async throws -> Operations.GetMALConnection.Output {
        let status = try await services.malConnect.status(userID: currentUser())
        return .ok(.init(body: .json(.init(
            connected: status.connected, username: status.username, connectedAt: status.connectedAt,
            needsReconnect: status.needsReconnect
        ))))
    }

    func disconnectMAL(_: Operations.DisconnectMAL.Input) async throws -> Operations.DisconnectMAL.Output {
        try await services.malConnect.disconnect(userID: currentUser())
        return .noContent(.init())
    }
}
