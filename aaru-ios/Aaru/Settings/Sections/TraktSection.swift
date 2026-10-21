import AaruAPI
import AuthenticationServices
import SwiftUI

/// IMP-002/003: each user connects their own Trakt account, then imports it like any other
/// source. The server holds the PKCE verifier and the sealed tokens; the sign-in sheet only
/// carries Trakt's page and, at the end, Aaru's `aaru://…?trakt=` return address.
struct TraktSection: View {
    let api: Client?
    /// Shows a failure in Settings' problem banner.
    var onProblem: (String) -> Void
    /// Opens the new import so the user can review its plan.
    var onImported: (ImportJob) -> Void

    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var connection: Components.Schemas.TraktConnection?
    @State private var busy = false

    private static let returnTo = "aaru://settings/trakt"

    var body: some View {
        Section {
            if let connection, connection.connected {
                LabeledContent("Connected as", value: connection.username ?? "your Trakt account")
                Button {
                    Task { await startImport() }
                } label: {
                    row("Import from Trakt", systemImage: "arrow.down.circle")
                }
                .disabled(busy)
                Button("Disconnect Trakt", role: .destructive) { Task { await disconnect() } }
                    .disabled(busy)
            } else {
                Button {
                    Task { await connect() }
                } label: {
                    row("Connect Trakt", systemImage: "link")
                }
                .disabled(busy || api == nil || connection == nil)
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
        .task { await load() }
    }

    private func row(_ title: String, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            if busy {
                Spacer()
                ProgressView()
            }
        }
    }

    private func load() async {
        guard let api else { return }
        if case let .ok(response) = try? await api.getTraktConnection() {
            connection = try? response.body.json
        }
    }

    private func connect() async {
        guard let api else { return }
        busy = true
        defer { busy = false }
        do {
            guard case let .ok(response) = try await api.connectTrakt(body: .json(.init(returnTo: Self.returnTo))),
                  let page = try URL(string: response.body.json.authorizeUrl)
            else { return onProblem("Trakt is not available right now. Try again later.") }
            let callback = try await webAuthenticationSession.authenticate(using: page, callbackURLScheme: "aaru")
            let result = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "trakt" }?.value
            switch result {
            case "connected": await load()
            case "denied": break
            default:
                onProblem(
                    "Trakt could not finish connecting. Free Trakt accounts can connect two apps; "
                        + "disconnect one on trakt.tv, or try again."
                )
            }
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return
        } catch {
            onProblem("Trakt could not be reached. Aaru could not reach the server.")
        }
    }

    private func startImport() async {
        guard let api else { return }
        busy = true
        defer { busy = false }
        do {
            switch try await api.createTraktImport() {
            case let .accepted(response):
                try onImported(response.body.json)
            case let .default(_, error):
                onProblem((try? error.body.json.message) ?? "That Trakt import could not be started.")
            }
        } catch {
            onProblem("The import did not start. Aaru could not reach the server.")
        }
    }

    private func disconnect() async {
        guard let api else { return }
        busy = true
        defer { busy = false }
        do {
            switch try await api.disconnectTrakt() {
            case .noContent:
                connection = .init(connected: false)
            case let .default(_, error):
                onProblem((try? error.body.json.message) ?? "Trakt was not disconnected. Try again.")
            }
        } catch {
            onProblem("Trakt was not disconnected. Aaru could not reach the server.")
        }
    }
}
