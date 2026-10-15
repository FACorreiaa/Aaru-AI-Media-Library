import aaruAPI
import AaruCore
import Foundation
import OpenAPIRuntime

extension APIImplementation {
    func registerDevice(_ input: Operations.RegisterDevice.Input) async throws -> Operations.RegisterDevice.Output {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let token = body.token.trimmingCharacters(in: .whitespaces).lowercased()
        guard (32 ... 200).contains(token.count), token.allSatisfy(\.isHexDigit) else {
            throw AppError(
                status: .unprocessableContent, code: "validation_failed",
                message: "That is not an APNs device token.", details: ["token": "Hex, as the device gave it."]
            )
        }
        guard PushTopics.allowed.contains(body.bundleId) else {
            throw AppError(
                status: .unprocessableContent, code: "validation_failed",
                message: "Unknown app.", details: ["bundleId": "Not an Aaru app."]
            )
        }
        let environment: PushEnvironment = body.environment == .production ? .production : .sandbox
        try await stores.push.register(
            PushDevice(token: token, environment: environment, topic: body.bundleId), userID: currentUser()
        )
        return .noContent(.init())
    }

    func unregisterDevice(_ input: Operations.UnregisterDevice.Input) async throws -> Operations.UnregisterDevice
        .Output
    {
        try await stores.push.unregister(token: input.path.token.lowercased(), userID: currentUser())
        return .noContent(.init())
    }

    func getNotificationSettings(_: Operations.GetNotificationSettings.Input) async throws
        -> Operations.GetNotificationSettings.Output
    {
        try await .ok(.init(body: .json(.init(airing: stores.push.airingEnabled(userID: currentUser())))))
    }

    func updateNotificationSettings(_ input: Operations.UpdateNotificationSettings.Input) async throws
        -> Operations.UpdateNotificationSettings.Output
    {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let userID = try currentUser()
        try await stores.push.setAiring(body.airing, userID: userID, now: Date())
        return try await .ok(.init(body: .json(.init(airing: stores.push.airingEnabled(userID: userID)))))
    }
}
