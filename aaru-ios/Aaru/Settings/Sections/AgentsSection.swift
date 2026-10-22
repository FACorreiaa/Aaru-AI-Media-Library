import SwiftUI

/// Connections → Agents (OUT-004): AI agents that reach the library over MCP, and the browser
/// extension (SCR-007). Lists the live ones, disconnects them, and opens the setup sheet that
/// mints an MCP token. The extension connects from the desktop browser itself.
struct AgentsSection: View {
    let model: ConnectionsModel

    @State private var connecting = false
    @State private var showsExtension = false
    @State private var disconnecting: AgentToken?

    var body: some View {
        Section {
            if !model.hasLoaded, model.isAvailable {
                ProgressView().frame(maxWidth: .infinity)
            }
            ForEach(model.agents, id: \.id) { token in
                ConnectionRow(token: token, detail: detail(token)) { disconnecting = token }
            }
            Button("Connect an agent", systemImage: "sparkles") { connecting = true }
                .disabled(!model.isAvailable)
            Button("Browser extension", systemImage: "puzzlepiece.extension") { showsExtension = true }
        } header: {
            Text("Agents")
        } footer: {
            Text(
                "Claude, Claude Code, Codex, Hermes, Gemini CLI or any MCP client can read your library. If you allow "
                    + "changes, it changes one item at a time, and you can undo it in History, in Your data. The "
                    + "browser extension marks what you finish on streaming sites."
            )
        }
        .confirmsDisconnect($disconnecting, stops: { token in
            token.kind == .browser
                ? "This browser stops marking what you watch."
                : "\(token.name) can no longer reach your library."
        }, perform: { token in
            Task { await model.disconnect(token) }
        })
        .sheet(isPresented: $connecting) {
            ConnectionSetupView(model: model)
        }
        .sheet(isPresented: $showsExtension) {
            BrowserExtensionView()
        }
    }

    private func detail(_ token: AgentToken) -> Text {
        let used = ConnectionRow.lastUsed(token)
        if token.kind == .browser {
            return Text("Marks what you watch · \(used)")
        }
        var access = token.scopes.contains(.library_colon_write) ? "Can change one item at a time" : "Read only"
        if token.scopes.contains(.imports_colon_write) {
            access += " · can send imports"
        }
        return Text("\(ConnectionSetupView.label(token.kind)) · \(access) · \(used)")
    }
}
