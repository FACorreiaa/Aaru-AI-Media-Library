import AaruCore
import Foundation

/// Avatars (SOC-001b, owner 2026-10-27): one square JPEG per user, prepared on the device. It
/// goes wherever the name goes, to signed-in accounts only; a block either way is the same 404
/// as no avatar.
extension SocialService {
    /// Apps send 512px at quality 0.85, far under this.
    static let maxAvatarBytes = 1024 * 1024

    static let noAvatar = AppError.notFound("No such avatar.")

    func saveAvatar(_ userID: UserID, image: Data) async throws -> UserProfile {
        guard image.starts(with: [0xFF, 0xD8, 0xFF]) else {
            throw AppError(
                status: .unsupportedMediaType, code: "avatar_image_type", message: "Send the photo as a JPEG."
            )
        }
        try await stores.social.saveAvatar(userID, image: image)
        return try await profile(userID)
    }

    func removeAvatar(_ userID: UserID) async throws -> UserProfile {
        try await stores.social.deleteAvatar(userID)
        return try await profile(userID)
    }

    func avatar(of owner: UserID, viewer: UserID) async throws -> Data {
        if owner != viewer, try await stores.social.isBlocked(viewer, owner) {
            throw Self.noAvatar
        }
        guard let image = try await stores.social.avatar(owner) else { throw Self.noAvatar }
        return image
    }

    private func profile(_ userID: UserID) async throws -> UserProfile {
        guard let profile = try await stores.users.profile(userID) else { throw AppError.unauthorized() }
        return profile
    }
}
