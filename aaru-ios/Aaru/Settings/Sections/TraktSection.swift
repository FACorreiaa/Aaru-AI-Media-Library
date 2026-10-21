import AuthenticationServices
import SwiftUI

/// IMP-002/003: each user connects their own Trakt account, then imports it like any other
/// source. The server holds the PKCE verifier and the sealed tokens; the sign-in sheet only
/// carries Trakt's page and, at the end, Aaru's `aaru://…?trakt=` return address.
struct TraktSection: View {
    let imports: ImportsModel
    /// Opens the new import so the user can review its plan.
    var onImported: (ImportJob) -> Void

    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    var body: some View {
        Section {
            if let connection = imports.trakt, connection.connected {
                LabeledContent("Connected as", value: connection.username ?? "your Trakt account")
                Button(action: startImport) {
                    row("Import from Trakt", systemImage: "arrow.down.circle")
                }
                .disabled(imports.traktBusy)
                Button("Disconnect Trakt", role: .destructive) { Task { await imports.disconnectTrakt() } }
                    .disabled(imports.traktBusy)
            } else {
                Button(action: connect) {
                    row("Connect Trakt", systemImage: "link")
                }
                .disabled(imports.traktBusy || imports.trakt == nil)
            }
        } header: {
            Text("Trakt")
        } footer: {
            Text(
                "Aaru reads your watched history, episodes, watchlist, ratings and lists, and shows you the plan "
                    + "first. Importing again only fills gaps. Free Trakt accounts can connect two apps.\n\n"
                    + "Aaru uses Trakt but is not endorsed or certified by Trakt."
            )
        }
        .task { await imports.loadTrakt() }
    }

    private func row(_ title: String, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            if imports.traktBusy {
                Spacer()
                ProgressView()
            }
        }
    }

    private func connect() {
        Task {
            guard let page = await imports.traktAuthorizeURL() else { return }
            do {
                let callback = try await webAuthenticationSession.authenticate(using: page, callbackURLScheme: "aaru")
                await imports.finishTrakt(callback)
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                return
            } catch {
                imports.problem = "Trakt could not be reached. Try again."
            }
        }
    }

    private func startImport() {
        Task {
            if let job = await imports.startTraktImport() {
                onImported(job)
            }
        }
    }
}
