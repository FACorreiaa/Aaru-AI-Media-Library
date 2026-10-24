import AuthenticationServices
import SwiftUI

/// Connections → MyAnimeList (SCR-005): each user connects their own MAL account; from then on
/// the server pushes anime progress. The server holds the PKCE verifier and the sealed tokens;
/// the sign-in sheet only carries MAL's page and, at the end, Aaru's `aaru://…?mal=` return.
struct MALSection: View {
    let model: ConnectionsModel

    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var confirmingDisconnect = false

    var body: some View {
        Section {
            if let connection = model.mal, connection.connected {
                if connection.needsReconnect {
                    Label("MyAnimeList stopped accepting Aaru. Nothing is sent until you reconnect.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color(.danger))
                    Button(action: connect) { row("Reconnect", systemImage: "arrow.clockwise") }
                        .disabled(model.malBusy)
                } else {
                    LabeledContent("Connected as", value: connection.username ?? "your MyAnimeList account")
                    if let since = connection.connectedAt {
                        LabeledContent("Since") { Text(since, format: .dateTime.day().month()) }
                    }
                }
                Button("Disconnect", role: .destructive) { confirmingDisconnect = true }
                    .disabled(model.malBusy)
            } else {
                Button(action: connect) { row("Connect MyAnimeList", systemImage: "link") }
                    .disabled(model.malBusy || model.mal == nil)
            }
        } header: {
            Text("MyAnimeList")
        } footer: {
            Text(
                "Anime you update in Aaru update your MyAnimeList list too: status, watched episodes and score, "
                    + "one entry per season. Only changes from now on go; your list is not overwritten. "
                    + "Removing an anime here leaves it on MyAnimeList."
            )
        }
        .confirmationDialog("Disconnect MyAnimeList?", isPresented: $confirmingDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { Task { await model.disconnectMAL() } }
        } message: {
            Text("Aaru stops updating your MyAnimeList list. Both lists stay as they are.")
        }
    }

    private func row(_ title: String, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            if model.malBusy {
                Spacer()
                ProgressView()
            }
        }
    }

    private func connect() {
        Task {
            guard let page = await model.malAuthorizeURL() else { return }
            do {
                let callback = try await webAuthenticationSession.authenticate(using: page, callbackURLScheme: "aaru")
                await model.finishMAL(callback)
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                return
            } catch {
                model.problem = "MyAnimeList could not be reached. Try again."
            }
        }
    }
}
