import AaruAPI
import AuthenticationServices
import CryptoKit
import Foundation

/// Sign-in and sign-out against `/v1/auth` (APP-002). Views call this; it owns the session writes.
@MainActor
struct AuthFlow {
    let api: Client?
    let session: SessionStore

    // MARK: Sign in with Apple

    func signInWithApple(_ authorization: ASAuthorization, rawNonce: String) async throws {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.identityToken,
              let identityToken = String(bytes: data, encoding: .utf8)
        else { throw AuthFlowError("Apple did not return a sign-in token. Try again.") }
        // Apple shares the name only on the first authorization; the server keeps it then.
        let name = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) }
        let output = try await client().signInWithApple(body: .json(.init(
            identityToken: identityToken,
            nonce: rawNonce,
            displayName: name?.isEmpty == false ? name : nil
        )))
        switch output {
        case let .ok(success): try session.signIn(token: success.body.json.token)
        case let .default(_, error): throw try AuthFlowError(error.body.json.message)
        }
    }

    // MARK: Sign in with Google (AUTH-005)

    func signInWithGoogle(_ token: GoogleSignIn.Token) async throws {
        switch try await client().signInWithGoogle(body: .json(.init(idToken: token.idToken, nonce: token.nonce))) {
        case let .ok(success): try session.signIn(token: success.body.json.token)
        case let .default(_, error): throw try AuthFlowError(error.body.json.message)
        }
    }

    /// Adds Google to the signed-in account. Refused when that Google account is already another
    /// Aaru account's; the two are never merged.
    func linkGoogle(_ token: GoogleSignIn.Token) async throws -> Components.Schemas.Me {
        switch try await client().linkGoogle(body: .json(.init(idToken: token.idToken, nonce: token.nonce))) {
        case let .ok(success): return try success.body.json
        case let .default(_, error): throw try AuthFlowError(error.body.json.message)
        }
    }

    // MARK: Email code

    func sendCode(to email: String) async throws {
        switch try await client().requestMagicLink(body: .json(.init(email: email))) {
        case .accepted: return
        case let .default(_, error): throw try AuthFlowError(error.body.json.message)
        }
    }

    func signIn(email: String, code: String) async throws {
        switch try await client().verifyMagicLink(body: .json(.init(email: email, code: code))) {
        case let .ok(success): try session.signIn(token: success.body.json.token)
        case let .default(_, error): throw try AuthFlowError(error.body.json.message)
        }
    }

    // MARK: Sign out

    /// Ends the session on the server when it can, and always on this device.
    func signOut() async {
        #if os(iOS)
            await PushRegistrar.current?.forgetDevice()
        #endif
        _ = try? await api?.signOut()
        session.signOut()
    }

    /// Deletes the account on the server, then signs out here. Returns a message on failure.
    func deleteAccount() async -> String? {
        guard let api else { return "This build has no server configured." }
        do {
            switch try await api.deleteAccount() {
            case .noContent:
                session.signOut()
                return nil
            case let .default(_, error):
                return (try? error.body.json.message) ?? "The account was not deleted."
            }
        } catch {
            return "The account was not deleted. Aaru could not reach the server."
        }
    }

    private func client() throws -> Client {
        guard let api else { throw AuthFlowError("This build has no server configured.") }
        return api
    }
}

struct AuthFlowError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

/// The Sign in with Apple nonce: the raw value goes to Aaru, its SHA-256 to Apple.
enum SignInNonce {
    static func make() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0 ..< 32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator)) }
            .joined()
    }

    static func sha256(_ raw: String) -> String {
        SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
