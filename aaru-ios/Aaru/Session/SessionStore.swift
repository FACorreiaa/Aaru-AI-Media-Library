import Observation

/// The signed-in session the UI routes on. APP-002 keeps the token in the Keychain.
@MainActor
@Observable
final class SessionStore {
    private(set) var token: String?

    var isSignedIn: Bool {
        token != nil
    }

    func signIn(token: String) {
        self.token = token
    }

    /// The server refused the session (a 401): back to the welcome screen, once.
    func sessionWasRejected() {
        token = nil
    }
}
