import AaruAPI
import Foundation
import Observation

/// Settings → Account: who is signed in and how (GET /v1/me), and linking Google (AUTH-005).
/// The name and handle are `SocialModel`'s; Account shows its editor.
@MainActor
@Observable
final class AccountModel {
    private(set) var me: Components.Schemas.Me?
    private(set) var linking = false
    var problem: String?

    @ObservationIgnored private let api: Client?

    init(api: Client?) {
        self.api = api
    }

    var canLinkGoogle: Bool {
        api != nil && AppEnvironment.googleClientID != nil && me.map { !$0.providers.contains(.google) } == true
    }

    /// "Apple, Email", or "—" before the account loads.
    var providers: String {
        let names = (me?.providers ?? []).map { provider in
            switch provider {
            case .apple: "Apple"
            case .google: "Google"
            case .email: "Email"
            }
        }
        return names.isEmpty ? "—" : names.joined(separator: ", ")
    }

    func load() async {
        guard let api else { return }
        do {
            if case let .ok(response) = try await api.getMe() {
                me = try response.body.json
            }
        } catch {
            problem = "Your account could not be loaded. Aaru could not reach the server."
        }
    }

    /// Adds Google to this account with the ID token Google's sheet returned.
    func linkGoogle(_ token: GoogleSignIn.Token) async {
        guard let api else { return }
        linking = true
        problem = nil
        defer { linking = false }
        do {
            switch try await api.linkGoogle(body: .json(.init(idToken: token.idToken, nonce: token.nonce))) {
            case let .ok(success):
                me = try success.body.json
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "Google was not linked."
            }
        } catch {
            problem = "Google was not linked. Aaru could not reach the server."
        }
    }

    func reset() {
        me = nil
        problem = nil
    }
}
