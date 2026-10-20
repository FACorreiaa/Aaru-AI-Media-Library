import AaruAPI
import SwiftUI

/// "Connect Stremio" (GET/POST/DELETE /v1/agent/tokens): mints a token whose install link adds
/// Aaru's addon to Stremio, lists the links already made, and revokes them.
struct StremioSection: View {
    let api: Client?
    let imports: ImportsModel
    /// Shows a failure in Settings' problem banner.
    var onProblem: (String) -> Void
    /// Opens a history import once Stremio approved it (IMP-016).
    var onImported: (ImportJob) -> Void

    @State private var tokens: [Components.Schemas.AgentToken] = []
    @State private var loaded = false
    @State private var allowsLibraryWrites = false
    @State private var connecting = false
    /// The new link. The server shows it once, so it lives here until the user is done with it.
    @State private var created: Components.Schemas.AgentTokenCreated?
    @State private var copied = false
    @State private var revoking: Components.Schemas.AgentToken?
    @State private var importsHistory = false

    var body: some View {
        Section {
            StremioGuide()
            if !loaded, api != nil {
                ProgressView().frame(maxWidth: .infinity)
            }
            ForEach(tokens, id: \.id) { token in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(token.name).foregroundStyle(Color(.ink))
                        lastUsed(token).font(.caption).foregroundStyle(Color(.muted))
                    }
                    Spacer()
                    Button("Revoke", role: .destructive) { revoking = token }
                        .buttonStyle(.borderless)
                }
            }
            if let created {
                createdRows(created)
            } else {
                Toggle(isOn: $allowsLibraryWrites) {
                    Text("Allow Stremio to change my library")
                    Text("Marking unwatched and adding to Stremio's library reach Aaru. Removing never deletes here.")
                }
                .disabled(connecting)
                Button {
                    Task { await connect() }
                } label: {
                    HStack {
                        Label("Connect Stremio", systemImage: "play.tv")
                        if connecting {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(connecting || api == nil)
            }
            Button {
                importsHistory = true
            } label: {
                Label("Import my Stremio history", systemImage: "clock.arrow.circlepath")
            }
            .disabled(api == nil)
        } header: {
            Text("Stremio")
        } footer: {
            if created != nil {
                Text(
                    "This link is shown only once and works like a password: anyone with it can see your "
                        + "library. Revoke it if you shared it by mistake."
                )
            } else {
                Text(
                    "Your Continue watching, Next 7 days and Plan to watch show up in Stremio, and episodes you "
                        + "play there tick off here. Works with Stremio Web and Stremio 5 desktop. "
                        + "Importing your history brings in what you watched before, once."
                )
            }
        }
        .confirmationDialog(
            "Revoke this Stremio link?",
            isPresented: Binding(get: { revoking != nil }, set: {
                if !$0 {
                    revoking = nil
                }
            }),
            titleVisibility: .visible,
            presenting: revoking
        ) { token in
            Button("Revoke", role: .destructive) { Task { await revoke(token) } }
        } message: { _ in
            Text("Stremio stops showing your Aaru library.")
        }
        .sheet(isPresented: $importsHistory) {
            StremioHistoryImport(imports: imports, onImported: onImported)
        }
        .task { await load() }
    }

    @ViewBuilder
    private func createdRows(_ created: Components.Schemas.AgentTokenCreated) -> some View {
        if let links = created.stremio {
            if let install = URL(string: links.installUrl) {
                Link(destination: install) { Label("Open in Stremio", systemImage: "arrow.up.forward.app") }
            }
            if let web = URL(string: links.webInstallUrl) {
                Link(destination: web) { Label("Install on Stremio Web", systemImage: "safari") }
            }
            Button {
                copy(links.manifestUrl)
            } label: {
                Label(copied ? "Copied" : "Copy link", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            if let manifest = URL(string: links.manifestUrl) {
                ShareLink(item: manifest) { Label("Share link", systemImage: "square.and.arrow.up") }
            }
        }
        Button("Done") {
            self.created = nil
            copied = false
        }
    }

    private func lastUsed(_ token: Components.Schemas.AgentToken) -> Text {
        if let date = token.lastUsedAt {
            Text("Last used \(date, format: .relative(presentation: .named))")
        } else {
            Text("Not used yet")
        }
    }

    private func load() async {
        guard let api else { return }
        defer { loaded = true }
        do {
            switch try await api.listAgentTokens(query: .init(_for: .stremio)) {
            case let .ok(response):
                tokens = try response.body.json.items.filter { $0.kind == .stremio }
            case let .default(_, error):
                onProblem((try? error.body.json.message) ?? "Your Stremio links could not be loaded.")
            }
        } catch {
            onProblem("Your Stremio links could not be loaded. Aaru could not reach the server.")
        }
    }

    private func connect() async {
        guard let api else { return }
        connecting = true
        defer { connecting = false }
        do {
            let body = Components.Schemas.AgentTokenCreate(kind: .stremio, allowLibraryWrites: allowsLibraryWrites)
            switch try await api.createAgentToken(body: .json(body)) {
            case let .created(response):
                let result = try response.body.json
                tokens.insert(result.token, at: 0)
                copied = false
                created = result
            case let .default(_, error):
                onProblem((try? error.body.json.message) ?? "Stremio could not be connected.")
            }
        } catch {
            onProblem("Stremio could not be connected. Aaru could not reach the server.")
        }
    }

    private func revoke(_ token: Components.Schemas.AgentToken) async {
        guard let api else { return }
        do {
            switch try await api.revokeAgentToken(path: .init(id: token.id)) {
            case .noContent:
                tokens.removeAll { $0.id == token.id }
                if created?.token.id == token.id {
                    created = nil
                }
            case let .default(_, error):
                onProblem((try? error.body.json.message) ?? "That Stremio link was not revoked.")
            }
        } catch {
            onProblem("That Stremio link was not revoked. Aaru could not reach the server.")
        }
    }

    private func copy(_ text: String) {
        #if os(iOS)
            UIPasteboard.general.string = text
        #elseif os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        #endif
        copied = true
    }
}

/// The setup steps, so nobody has to leave the app to learn how the addon works. Same text as
/// the web's `StremioGuide`.
private struct StremioGuide: View {
    private static let steps = [
        "Choose whether Stremio may also change your library, then tap Connect Stremio.",
        "Tap Open in Stremio for the desktop app or Install on Stremio Web in a browser. Or copy the link "
            + "and paste it into the search box on Stremio’s Addons page.",
        "Approve the install in Stremio. Your rows appear on Stremio’s board and load as you scroll to them.",
    ]

    private static let behaviour = [
        "Marking an episode or film watched in Stremio ticks it here. It shows in your history with an undo.",
        "Finishing an episode in Stremio’s player ticks it too.",
        "Unmarking and adding titles reach Aaru only if you allowed it when connecting. Removing a title in "
            + "Stremio never removes it here.",
        "Aaru adds no streams. You play things with the add-ons you already use.",
        "What you tick in Aaru does not show as watched in Stremio.",
        "Works with Stremio Web and Stremio 5 on desktop. The phone and TV apps are not confirmed yet.",
    ]

    var body: some View {
        DisclosureGroup("How to set it up") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                    row("\(index + 1).", step)
                }
                heading("What it does")
                ForEach(Self.behaviour, id: \.self) { line in
                    row("•", line)
                }
                heading("History and lost links")
                Text(
                    "Import my Stremio history brings in what you watched before, once: approve the code on "
                        + "stremio.com, then review the import before anything changes. The install link is shown "
                        + "only once. If you lose it, revoke it and connect again."
                )
            }
            .font(.subheadline)
            .foregroundStyle(Color(.muted))
            .padding(.vertical, 4)
        }
    }

    private func row(_ marker: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(marker).monospacedDigit()
            Text(text)
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text).fontWeight(.semibold).foregroundStyle(Color(.ink)).padding(.top, 4)
    }
}
