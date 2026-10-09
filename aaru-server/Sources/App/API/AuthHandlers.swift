import aaruAPI
import Foundation
import OpenAPIRuntime

extension APIImplementation {
    func signInWithApple(_ input: Operations.SignInWithApple.Input) async throws -> Operations.SignInWithApple.Output {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let session = try await auth.signInWithApple(
            identityToken: body.identityToken,
            rawNonce: body.nonce,
            displayName: body.displayName
        )
        return .ok(.init(body: .json(.init(session))))
    }

    func requestMagicLink(_ input: Operations.RequestMagicLink.Input) async throws -> Operations.RequestMagicLink
        .Output
    {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let address = try currentContext().clientAddressForRateLimit
        try await auth.requestMagicLink(email: body.email, clientAddress: address)
        return .accepted(.init())
    }

    func verifyMagicLink(_ input: Operations.VerifyMagicLink.Input) async throws -> Operations.VerifyMagicLink.Output {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let session = try await auth.verifyMagicLink(token: body.token)
        return .ok(.init(body: .json(.init(session))))
    }

    func signOut(_: Operations.SignOut.Input) async throws -> Operations.SignOut.Output {
        guard let hash = try currentContext().sessionTokenHash else { throw AppError.unauthorized() }
        try await auth.signOut(tokenHash: hash)
        return .noContent(.init())
    }

    func getMe(_: Operations.GetMe.Input) async throws -> Operations.GetMe.Output {
        let userID = try currentUser()
        guard let profile = try await stores.users.profile(userID) else { throw AppError.unauthorized() }
        return .ok(.init(body: .json(.init(
            userId: profile.id.description,
            displayName: profile.displayName,
            providers: profile.providers.compactMap { .init(rawValue: $0.rawValue) }
        ))))
    }

    func deleteAccount(_: Operations.DeleteAccount.Input) async throws -> Operations.DeleteAccount.Output {
        try await auth.deleteAccount(currentUser())
        return .noContent(.init())
    }
}

extension Components.Schemas.Session {
    init(_ session: NewSession) {
        self.init(token: session.token, userId: session.userID.description, expiresAt: session.expiresAt)
    }
}
