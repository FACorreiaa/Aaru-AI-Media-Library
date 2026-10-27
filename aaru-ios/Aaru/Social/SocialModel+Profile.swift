import AaruAPI
import Foundation
import OpenAPIRuntime

/// SOC-001b: your photo and whether friends see your email, beside the handle and names in
/// `SocialModel.swift`. Profile data: nothing here is journaled.
extension SocialModel {
    /// Saves the handle and both names (SOC-001b); an empty name clears it. A name needs no
    /// handle, but a handle once claimed can change and not go. True when saved.
    func saveProfile(handle: String, firstName: String, lastName: String) async -> Bool {
        let handle = Self.normalized(handle)
        if !handle.isEmpty || self.handle != nil, let invalid = Self.handleProblem(handle) {
            problem = invalid
            return false
        }
        guard let api else { return false }
        let body = Components.Schemas.ProfileUpdate(
            handle: handle.isEmpty ? nil : handle, firstName: firstName, lastName: lastName
        )
        return await run("Your profile was not saved.") {
            switch try await api.updateProfile(body: .json(body)) {
            case let .ok(response): try adopt(response.body.json)
            case let .default(_, error): throw Failure(try? error.body.json.message)
            }
        }
    }

    /// Replaces the photo with the square JPEG `AvatarImage.jpeg` made. True when saved.
    func uploadAvatar(_ jpeg: Data) async -> Bool {
        guard let api else { return false }
        return await run("Your photo was not saved.") {
            switch try await api.uploadAvatar(body: .jpeg(HTTPBody(jpeg))) {
            case let .ok(response): try adopt(response.body.json)
            case let .default(_, error): throw Failure(try? error.body.json.message)
            }
        }
    }

    func removeAvatar() async {
        guard let api else { return }
        await run("Your photo was not removed.") {
            switch try await api.deleteAvatar() {
            case let .ok(response): try adopt(response.body.json)
            case let .default(_, error): throw Failure(try? error.body.json.message)
            }
        }
    }

    /// Turns "Friends can see my email" on or off at once, and back if the server says no.
    func setShareEmail(_ share: Bool) async {
        guard let api else { return }
        let previous = shareEmail
        shareEmail = share
        let body = Components.Schemas.SocialSettings(
            shareLibraryWithFriends: shareLibrary, shareEmailWithFriends: share
        )
        let saved = await run("That was not saved.") {
            switch try await api.updateSocialSettings(body: .json(body)) {
            case .ok: break
            case let .default(_, error): throw Failure(try? error.body.json.message)
            }
        }
        if !saved {
            shareEmail = previous
        }
    }
}
