import Foundation
import Observation

/// The signed-in session the UI routes on, kept in the Keychain (APP-002).
@MainActor
@Observable
final class SessionStore {
    private(set) var token: String?
    @ObservationIgnored private let keychain: SessionKeychain

    init(keychain: SessionKeychain = SessionKeychain()) {
        self.keychain = keychain
        token = keychain.read()
        #if DEBUG
            // Simulator checks without typing a code: `simctl launch … -AaruDebugSessionToken <token>`.
            if let debugToken = UserDefaults.standard.string(forKey: "AaruDebugSessionToken") {
                token = debugToken
            }
        #endif
    }

    var isSignedIn: Bool {
        token != nil
    }

    func signIn(token: String) {
        self.token = token
        keychain.save(token)
    }

    func signOut() {
        token = nil
        keychain.delete()
    }

    /// The server refused the session (a 401): back to the welcome screen, once.
    func sessionWasRejected() {
        signOut()
    }
}
