import AaruAPI
import SwiftUI

/// AUTH-005: adds Google to the signed-in account, so either sign-in opens one library.
struct LinkGoogleButton: View {
    let api: Client?
    let clientID: String
    @Binding var account: Components.Schemas.Me?

    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var linking = false
    @State private var problem: String?

    var body: some View {
        Button {
            Task { await link() }
        } label: {
            HStack {
                Text("Link Google account")
                if linking {
                    Spacer()
                    ProgressView()
                }
            }
        }
        .disabled(linking || api == nil)
        if let problem {
            Text(problem)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    private func link() async {
        guard let api else { return }
        linking = true
        defer { linking = false }
        do {
            guard let token = try await GoogleSignIn(clientID: clientID).token(using: webAuthenticationSession)
            else { return }
            switch try await api.linkGoogle(body: .json(.init(idToken: token.idToken, nonce: token.nonce))) {
            case let .ok(success):
                account = try success.body.json
                problem = nil
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "Google was not linked."
            }
        } catch {
            problem = error.localizedDescription
        }
    }
}
