import AaruAPI
import SwiftUI

/// Settings → Connections (§18, UX-023): what reaches Aaru with a token of its own. Agents over
/// MCP and the browser extension, the Stremio addon, and music scrobblers. One verb ends any of
/// them: Disconnect (UX-024).
struct ConnectionsPage: View {
    let model: ConnectionsModel
    /// Music's "last listen" opens Listens.
    let api: Client?

    var body: some View {
        @Bindable var model = model
        Form {
            AgentsSection(model: model)
            StremioSection(model: model)
            MusicSection(model: model, api: api)
        }
        .settingsPage("Connections", problem: $model.problem)
        .refreshable { await model.load() }
        .task { await model.load() }
    }
}

/// A connection's row: its name, what it may do and when it was last used, and Disconnect.
struct ConnectionRow: View {
    let token: AgentToken
    let detail: Text
    var onDisconnect: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(token.name).foregroundStyle(Color(.ink))
                detail.font(.caption).foregroundStyle(Color(.muted))
            }
            Spacer(minLength: 8)
            Button("Disconnect", role: .destructive, action: onDisconnect)
                .buttonStyle(.borderless)
        }
        .contextMenu {
            Button("Disconnect", systemImage: "xmark.circle", role: .destructive, action: onDisconnect)
        }
    }

    /// "Used 3 days ago", or "Not used yet".
    static func lastUsed(_ token: AgentToken) -> Text {
        if let date = token.lastUsedAt {
            Text("Used \(date, format: .relative(presentation: .named))")
        } else {
            Text("Not used yet")
        }
    }
}

extension View {
    /// The one confirm for ending a connection; the message says what stops (UX-024).
    func confirmsDisconnect(
        _ token: Binding<AgentToken?>, stops: @escaping (AgentToken) -> String,
        perform: @escaping (AgentToken) -> Void
    ) -> some View {
        confirmationDialog(
            "Disconnect \(token.wrappedValue?.name ?? "this connection")?",
            isPresented: token.isPresent,
            titleVisibility: .visible,
            presenting: token.wrappedValue
        ) { token in
            Button("Disconnect", role: .destructive) { perform(token) }
        } message: { token in
            Text(stops(token))
        }
    }
}
