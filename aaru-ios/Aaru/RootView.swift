import AaruAPI
import SwiftUI

/// Routes on the session: welcome when signed out, the app when signed in.
struct RootView: View {
    let api: Client?
    @Environment(SessionStore.self) private var session
    @State private var showsSignInNotice = false

    var body: some View {
        if session.isSignedIn {
            // APP-003 replaces this with the library.
            ContentUnavailableView(
                "Signed in",
                systemImage: "books.vertical",
                description: Text("Your library is next.")
            )
        } else {
            WelcomeView(
                api: api,
                onSignInWithApple: { showsSignInNotice = true },
                onContinueWithEmail: { showsSignInNotice = true }
            )
            .alert("Sign-in opens in the next beta", isPresented: $showsSignInNotice) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This build shows the welcome screen only. Thanks for testing Aaru.")
            }
        }
    }
}

#Preview {
    RootView(api: nil)
        .environment(SessionStore())
}
