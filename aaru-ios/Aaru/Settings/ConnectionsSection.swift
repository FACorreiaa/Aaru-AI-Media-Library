import AaruAPI
import SwiftUI

/// "Connections" (OUT-004): AI agents that reach the library over MCP. Lists the live ones,
/// revokes them, and opens the setup sheet that mints a token (GET/POST/DELETE /v1/agent/tokens).
struct ConnectionsSection: View {
    let api: Client?
    /// Shows a failure in Settings' problem banner.
    var onProblem: (String) -> Void

    @State private var tokens: [Components.Schemas.AgentToken] = []
    @State private var loaded = false
    @State private var connecting = false
    @State private var revoking: Components.Schemas.AgentToken?

    var body: some View {
        Section {
            if !loaded, api != nil {
                ProgressView().frame(maxWidth: .infinity)
            }
            ForEach(tokens, id: \.id) { token in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(token.name).foregroundStyle(Color(.ink))
                        detail(token).font(.caption).foregroundStyle(Color(.muted))
                    }
                    Spacer()
                    Button("Revoke", role: .destructive) { revoking = token }
                        .buttonStyle(.borderless)
                }
            }
            Button {
                connecting = true
            } label: {
                Label("Connect an agent", systemImage: "sparkles")
            }
            .disabled(api == nil)
        } header: {
            Text("Connections")
        } footer: {
            Text(
                "Claude Code, Codex, Hermes, Gemini CLI or any MCP client can read your library. If you allow "
                    + "changes, it changes one item at a time, and you can undo it here."
            )
        }
        .confirmationDialog(
            "Revoke this connection?",
            isPresented: Binding(get: { revoking != nil }, set: {
                if !$0 {
                    revoking = nil
                }
            }),
            titleVisibility: .visible,
            presenting: revoking
        ) { token in
            Button("Revoke", role: .destructive) { Task { await revoke(token) } }
        } message: { token in
            Text("\(token.name) can no longer reach your library.")
        }
        .sheet(isPresented: $connecting) {
            if let api {
                ConnectionSetupView(api: api) { created in
                    tokens.insert(created.token, at: 0)
                }
            }
        }
        .task { await load() }
    }

    private func detail(_ token: Components.Schemas.AgentToken) -> Text {
        let access = token.scopes.contains(.library_colon_write) ? "Can change one item at a time" : "Read only"
        let used = token.lastUsedAt.map { Text("used \($0, format: .relative(presentation: .named))") }
            ?? Text("not used yet")
        return Text("\(ConnectionSetupView.label(token.kind)) · \(access) · ") + used
    }

    private func load() async {
        guard let api else { return }
        defer { loaded = true }
        do {
            switch try await api.listAgentTokens(query: .init(_for: .mcp)) {
            case let .ok(response):
                tokens = try response.body.json.items
            case let .default(_, error):
                onProblem((try? error.body.json.message) ?? "Your connections could not be loaded.")
            }
        } catch {
            onProblem("Your connections could not be loaded. Aaru could not reach the server.")
        }
    }

    private func revoke(_ token: Components.Schemas.AgentToken) async {
        guard let api else { return }
        do {
            switch try await api.revokeAgentToken(path: .init(id: token.id)) {
            case .noContent:
                tokens.removeAll { $0.id == token.id }
            case let .default(_, error):
                onProblem((try? error.body.json.message) ?? "That connection was not revoked.")
            }
        } catch {
            onProblem("That connection was not revoked. Aaru could not reach the server.")
        }
    }
}
