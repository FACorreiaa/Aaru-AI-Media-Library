import AaruAPI
import SwiftUI

/// Connections → Stremio: mints a token whose install link adds Aaru's addon to Stremio, lists
/// the links already made, and disconnects them. Stremio *history* is an import (UX-025).
struct StremioSection: View {
    let model: ConnectionsModel

    @Environment(AppRouter.self) private var router
    @State private var allowsLibraryWrites = false
    @State private var connecting = false
    /// The new link. The server shows it once, so it lives here until the user is done with it.
    @State private var created: AgentTokenCreated?
    @State private var copied = false
    @State private var disconnecting: AgentToken?

    var body: some View {
        Section {
            StremioGuide()
            ForEach(model.stremio, id: \.id) { token in
                ConnectionRow(token: token, detail: ConnectionRow.lastUsed(token)) { disconnecting = token }
            }
            if let created {
                StremioCreatedRows(created: created, copied: $copied) {
                    self.created = nil
                    copied = false
                }
            } else {
                Toggle(isOn: $allowsLibraryWrites) {
                    Text("Allow Stremio to change my library")
                    Text("Marking unwatched and adding to Stremio's library reach Aaru. Removing never deletes here.")
                }
                .disabled(connecting)
                Button(action: connect) {
                    HStack {
                        Label("Connect Stremio", systemImage: "play.tv")
                        if connecting {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(connecting || !model.isAvailable)
            }
            Button("Import your Stremio history", systemImage: "tray.and.arrow.down") {
                router.openSettings(.imports)
            }
        } header: {
            Text("Stremio")
        } footer: {
            if created != nil {
                Text(
                    "This link is shown only once and works like a password: anyone with it can see your "
                        + "library. Disconnect it if you shared it by mistake."
                )
            } else {
                Text(
                    "Your Continue watching, Next 7 days and Plan to watch show up in Stremio, and episodes you "
                        + "play there tick off here. Works with Stremio Web and Stremio 5 desktop."
                )
            }
        }
        .confirmsDisconnect($disconnecting, stops: { _ in "Stremio stops showing your Aaru library." }, perform: { token in
            if created?.token.id == token.id {
                created = nil
            }
            Task { await model.disconnect(token) }
        })
    }

    private func connect() {
        connecting = true
        Task {
            let body = Components.Schemas.AgentTokenCreate(kind: .stremio, allowLibraryWrites: allowsLibraryWrites)
            switch await model.create(body) {
            case let .success(result):
                copied = false
                created = result
            case let .failure(failure):
                model.problem = failure.message ?? "Stremio could not be connected."
            }
            connecting = false
        }
    }
}

/// The new link's ways in, shown once: open, install on the web, copy, share.
private struct StremioCreatedRows: View {
    let created: AgentTokenCreated
    @Binding var copied: Bool
    var onDone: () -> Void

    var body: some View {
        if let links = created.stremio {
            if let install = URL(string: links.installUrl) {
                Link(destination: install) { Label("Open in Stremio", systemImage: "arrow.up.forward.app") }
            }
            if let web = URL(string: links.webInstallUrl) {
                Link(destination: web) { Label("Install on Stremio Web", systemImage: "safari") }
            }
            Button {
                Pasteboard.copy(links.manifestUrl)
                copied = true
            } label: {
                Label(copied ? "Copied" : "Copy link", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            if let manifest = URL(string: links.manifestUrl) {
                ShareLink(item: manifest) { Label("Share link", systemImage: "square.and.arrow.up") }
            }
        }
        Button("Done", action: onDone)
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
                    "Stremio history, in Settings → Import, brings in what you watched before, once: approve "
                        + "the code on stremio.com, then review the import before anything changes. The install "
                        + "link is shown only once. If you lose it, disconnect it and connect again."
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
