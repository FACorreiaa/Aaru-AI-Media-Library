import SwiftUI

/// Signed-out shell until APP-001/APP-002 add the API client and session.
struct RootView: View {
    @State private var showsSignInNotice = false

    var body: some View {
        WelcomeView(
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

#Preview {
    RootView()
}
