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
        try await .ok(.init(body: .json(.init(stores.push.notificationSettings(userID: currentUser())))))
    }

    func updateNotificationSettings(_ input: Operations.UpdateNotificationSettings.Input) async throws
        -> Operations.UpdateNotificationSettings.Output
    {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let userID = try currentUser()
        var settings = try await stores.push.notificationSettings(userID: userID)
        settings.airing = body.airing ?? settings.airing
        settings.groupMentions = body.groupMentions ?? settings.groupMentions
        settings.groupInvites = body.groupInvites ?? settings.groupInvites
        try await stores.push.saveNotificationSettings(settings, userID: userID, now: Date())
        return try await .ok(.init(body: .json(.init(stores.push.notificationSettings(userID: userID)))))
    }
}

extension Components.Schemas.NotificationSettings {
    init(_ settings: NotificationSettings) {
        self.init(
            airing: settings.airing, groupMentions: settings.groupMentions, groupInvites: settings.groupInvites
        )
    }
}

// MARK: Web push

extension APIImplementation {
    func getWebPushKey(_: Operations.GetWebPushKey.Input) async throws -> Operations.GetWebPushKey.Output {
        _ = try currentUser()
        guard let webPush = services.webPush else { throw Self.webPushOff }
        return .ok(.init(body: .json(.init(publicKey: webPush.publicKey))))
    }

    func saveWebPushSubscription(_ input: Operations.SaveWebPushSubscription.Input) async throws
        -> Operations.SaveWebPushSubscription.Output
    {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        guard let webPush = services.webPush else { throw Self.webPushOff }
        guard WebPushEndpoints.isAllowed(body.endpoint) else {
            throw AppError(
                status: .unprocessableContent, code: "validation_failed",
                message: "That is not a browser push service.", details: ["endpoint": "Not a known push service."]
            )
        }
        let keys = [body.keys.p256dh, body.keys.auth]
        guard keys.allSatisfy({ (16 ... 200).contains($0.count) && $0.allSatisfy(Self.isBase64URL) }) else {
            throw AppError(
                status: .unprocessableContent, code: "validation_failed",
                message: "Those subscription keys are not valid.",
                details: ["keys": "base64url, as the browser gave them."]
            )
        }
        try await stores.push.saveWebPush(
            WebPushSubscription(
                endpoint: body.endpoint, p256dh: body.keys.p256dh, auth: body.keys.auth,
                vapidKeyID: webPush.publicKey
            ),
            userID: currentUser()
        )
        return .noContent(.init())
    }

    func deleteWebPushSubscription(_ input: Operations.DeleteWebPushSubscription.Input) async throws
        -> Operations.DeleteWebPushSubscription.Output
    {
        try await stores.push.deleteWebPush(endpoint: input.query.endpoint, userID: currentUser())
        return .noContent(.init())
    }

    private static let webPushOff = AppError(
        status: .serviceUnavailable, code: "push_unavailable", message: "Browser notifications are not set up yet."
    )

    private static func isBase64URL(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber || "-_=".contains(character))
    }
}
