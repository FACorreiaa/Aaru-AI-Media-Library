import SwiftUI

/// AUTH-005: adds Google to the signed-in account, so either sign-in opens one library.
struct LinkGoogleButton: View {
    let account: AccountModel
    let clientID: String

    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    var body: some View {
        Button(action: link) {
            HStack {
                Text("Link Google account")
                if account.linking {
                    Spacer()
                    ProgressView()
                }
            }
        }
        .disabled(account.linking)
    }

    private func link() {
        Task {
            do {
                guard let token = try await GoogleSignIn(clientID: clientID).token(using: webAuthenticationSession)
                else { return }
                await account.linkGoogle(token)
            } catch {
                account.problem = error.localizedDescription
            }
        }
    }
}
