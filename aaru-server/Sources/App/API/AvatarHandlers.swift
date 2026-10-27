import aaruAPI
import AaruCore
import Foundation
import OpenAPIRuntime

/// SOC-001b · avatars. Profile data like `PUT /v1/me/profile`: never journaled.
extension APIImplementation {
    func uploadAvatar(_ input: Operations.UploadAvatar.Input) async throws -> Operations.UploadAvatar.Output {
        guard case let .jpeg(body) = input.body else { throw AppError.badRequest() }
        let tooLarge = AppError(
            status: .contentTooLarge, code: "file_too_large", message: "That photo is larger than 1 MB."
        )
        if case let .known(length) = body.length, length > SocialService.maxAvatarBytes {
            throw tooLarge
        }
        let image: Data
        do {
            image = try await Data(collecting: body, upTo: SocialService.maxAvatarBytes)
        } catch {
            throw tooLarge
        }
        let profile = try await services.social.saveAvatar(currentUser(), image: image)
        return .ok(.init(body: .json(.init(profile))))
    }

    func deleteAvatar(_: Operations.DeleteAvatar.Input) async throws -> Operations.DeleteAvatar.Output {
        let profile = try await services.social.removeAvatar(currentUser())
        return .ok(.init(body: .json(.init(profile))))
    }

    func getUserAvatar(_ input: Operations.GetUserAvatar.Input) async throws -> Operations.GetUserAvatar.Output {
        guard let id = UUID(uuidString: input.path.userId) else { throw SocialService.noAvatar }
        let image = try await services.social.avatar(of: UserID(id), viewer: currentUser())
        // AvatarCacheMiddleware sets Cache-Control.
        return .ok(.init(body: .jpeg(HTTPBody(image))))
    }
}

extension SocialService {
    /// Where an avatar is read, with the version so caches never serve an old one.
    static func avatarPath(_ id: UserID, version: Int64) -> String {
        "/v1/users/\(id.description)/avatar?v=\(version)"
    }
}

extension Components.Schemas.Me {
    init(_ profile: UserProfile) {
        self.init(
            userId: profile.id.description,
            displayName: profile.displayName,
            firstName: profile.name.first,
            lastName: profile.name.last,
            handle: profile.handle,
            providers: profile.providers.compactMap { .init(rawValue: $0.rawValue) },
            email: profile.email,
            emailShareable: profile.emailShareable,
            avatarUrl: profile.avatarVersion.map { SocialService.avatarPath(profile.id, version: $0) }
        )
    }
}
