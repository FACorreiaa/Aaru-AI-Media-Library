import AuthenticationServices
import CryptoKit
import Foundation
import SwiftUI

/// Sign in with Google without Google's SDK (AUTH-005): the OAuth code flow with PKCE in the
/// system sign-in sheet, then the ID token goes to Aaru, which verifies it. An iOS-type client
/// has no secret, and the reversed client id is the redirect scheme Google allows for it.
struct GoogleSignIn {
    struct Token {
        let idToken: String
        let nonce: String
    }

    let clientID: String

    var callbackScheme: String {
        "com.googleusercontent.apps." + clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
    }

    private var redirectURI: String {
        callbackScheme + ":/oauth2redirect"
    }

    /// Nil when the user closed the sheet: not an error worth showing.
    func token(using session: WebAuthenticationSession) async throws -> Token? {
        let verifier = SignInNonce.make() + SignInNonce.make()
        let state = SignInNonce.make()
        let nonce = SignInNonce.make()
        let callback: URL
        do {
            callback = try await session.authenticate(
                using: authorizationURL(challenge: Self.challenge(for: verifier), state: state, nonce: nonce),
                callbackURLScheme: callbackScheme
            )
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return nil
        }
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }
        if value("error") == "access_denied" {
            return nil
        }
        guard value("state") == state, let code = value("code") else {
            throw AuthFlowError("Google did not finish the sign-in. Try again.")
        }
        return try await Token(idToken: exchange(code: code, verifier: verifier), nonce: nonce)
    }

    private static let authorizeURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")
    private static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")

    private func authorizationURL(challenge: String, state: String, nonce: String) throws -> URL {
        guard let base = Self.authorizeURL, var url = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else { throw AuthFlowError("Google sign-in is misconfigured.") }
        url.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "openid email profile"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "nonce", value: nonce),
            .init(name: "prompt", value: "select_account"),
        ]
        guard let result = url.url else { throw AuthFlowError("Google sign-in is misconfigured.") }
        return result
    }

    private func exchange(code: String, verifier: String) async throws -> String {
        guard let tokenURL = Self.tokenURL else { throw AuthFlowError("Google sign-in is misconfigured.") }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            .init(name: "code", value: code),
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "grant_type", value: "authorization_code"),
            .init(name: "code_verifier", value: verifier),
        ]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let idToken = try JSONDecoder().decode(GoogleTokenResponse.self, from: data).idToken
        else { throw AuthFlowError("Google did not return a sign-in token. Try again.") }
        return idToken
    }

    private static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private struct GoogleTokenResponse: Decodable {
    let idToken: String?

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
    }
}
