import AaruAPI
import AuthenticationServices
import SwiftUI

/// Routes on the session: welcome when signed out, the app when signed in.
struct RootView: View {
    let api: Client?
    let library: LibraryModel
    @Environment(SessionStore.self) private var session
    @State private var showsEmailSignIn = false
    @State private var errorMessage: String?

    private var flow: AuthFlow {
        AuthFlow(api: api, session: session)
    }

    var body: some View {
        Group {
            if session.isSignedIn {
                LibraryView(api: api, library: library) {
                    Task { await flow.signOut() }
                }
            } else {
                WelcomeView(
                    api: api,
                    onAppleAuthorization: { authorization, nonce in
                        Task { await run { try await flow.signInWithApple(authorization, rawNonce: nonce) } }
                    },
                    onAppleError: { error in
                        // Closing Apple's sheet is not an error worth showing.
                        if (error as? ASAuthorizationError)?.code != .canceled {
                            errorMessage = error.localizedDescription
                        }
                    },
                    onContinueWithEmail: { showsEmailSignIn = true }
                )
                .sheet(isPresented: $showsEmailSignIn) {
                    EmailSignInSheet(flow: flow)
                }
            }
        }
        // A signed-out device keeps nothing of the last user's library.
        .onChange(of: session.isSignedIn) { _, signedIn in
            if !signedIn {
                library.reset()
            }
        }
        .alert(
            "Could not sign in",
            isPresented: Binding(get: { errorMessage != nil }, set: {
                if !$0 {
                    errorMessage = nil
                }
            })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func run(_ action: () async throws -> Void) async {
        do {
            try await action()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    RootView(api: nil, library: LibraryModel())
        .environment(SessionStore(keychain: SessionKeychain(service: "preview")))
}
