import AaruAPI
import SwiftUI

/// Connect one scrobbler: pick it, connect, and the server answers its steps with the token
/// filled in, shown once. Then the sheet waits for the first listen so the user knows it works.
struct MusicSetupView: View {
    typealias Scrobbler = Components.Schemas.MusicScrobbler

    let model: ConnectionsModel
    /// The newest listen when the sheet opened; any other one is the scrobbler's first.
    let seen: Components.Schemas.Listen?

    @Environment(\.dismiss) private var dismiss
    @State private var scrobbler: Scrobbler = .webScrobbler
    @State private var created: Components.Schemas.AgentTokenCreated?
    @State private var working = false
    @State private var problem: String?
    @State private var copied: String?
    @State private var heard: Components.Schemas.Listen?
    @State private var gaveUp = false

    /// How long the sheet waits for the first listen, and how often it looks.
    private static let wait: Duration = .seconds(600)
    private static let poll: Duration = .seconds(5)

    var body: some View {
        NavigationStack {
            Form {
                if let setup = created?.music {
                    steps(setup)
                    Section {
                        firstListen
                    } footer: {
                        Text(
                            "The token is shown only now and works like a password: anyone with it can add listens "
                                + "to your log. Disconnect it if you shared it by mistake."
                        )
                    }
                } else {
                    Section {
                        Picker("Scrobbler", selection: $scrobbler) {
                            ForEach(Scrobbler.allCases, id: \.self) { scrobbler in
                                Text(Self.label(scrobbler)).tag(scrobbler)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } footer: {
                        Text(Self.summary(scrobbler))
                    }
                    Section {
                        Button {
                            Task { await create() }
                        } label: {
                            HStack {
                                Text("Connect \(Self.label(scrobbler))")
                                if working {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(working)
                    }
                }
                if let problem {
                    Section { Text(problem).foregroundStyle(Color(.danger)) }
                }
            }
            .paperPage()
            .navigationTitle("Connect a scrobbler")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(created == nil ? "Cancel" : "Done") { dismiss() }
                    }
                }
                .task(id: created?.token.id) { await waitForFirstListen() }
        }
        // A token shown once must not vanish on a stray swipe.
        .interactiveDismissDisabled(created != nil)
    }

    private func steps(_ setup: Components.Schemas.MusicSetup) -> some View {
        ForEach(Array(setup.steps.enumerated()), id: \.offset) { index, step in
            Section {
                Text(step.text)
                if let link = step.link, let url = URL(string: link.url) {
                    Link(destination: url) { Label(link.label, systemImage: "arrow.up.forward.app") }
                }
                ForEach(step.fields ?? [], id: \.label) { field in
                    copyRow(field)
                }
            } header: {
                Text("Step \(index + 1)")
            }
        }
    }

    private func copyRow(_ field: Components.Schemas.MusicSetup.StepsPayloadPayload.FieldsPayloadPayload)
        -> some View
    {
        let isCopied = copied == field.value
        return Button {
            copy(field.value)
        } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(field.label).font(.caption).foregroundStyle(Color(.muted))
                    Text(field.secret == true ? Self.masked(field.value) : field.value)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Color(.ink))
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Label(isCopied ? "Copied" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                    .labelStyle(.iconOnly)
            }
        }
        .accessibilityLabel("Copy \(field.label)")
    }

    @ViewBuilder
    private var firstListen: some View {
        if let heard {
            VStack(alignment: .leading, spacing: 2) {
                Label("Got it: \(heard.track) — \(heard.artist)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color(.ink))
                ListenDetail(listen: heard).font(.caption).foregroundStyle(Color(.muted))
            }
        } else if gaveUp {
            Text("No listen yet. Play a song, then check the scrobbler’s settings if nothing shows up here.")
                .foregroundStyle(Color(.muted))
        } else {
            HStack {
                ProgressView()
                Text("Waiting for your first listen…").foregroundStyle(Color(.muted))
            }
        }
    }

    /// Looks for a new listen every few seconds while the sheet is open; stops when one arrives,
    /// after ten minutes, or when the sheet closes.
    private func waitForFirstListen() async {
        guard created != nil else { return }
        let clock = ContinuousClock()
        let until = clock.now.advanced(by: Self.wait)
        while clock.now < until {
            do {
                try await Task.sleep(for: Self.poll)
            } catch {
                return
            }
            if let listen = await model.latestListenNow(), listen.id != seen?.id {
                heard = listen
                return
            }
        }
        gaveUp = true
    }

    private func create() async {
        working = true
        problem = nil
        defer { working = false }
        switch await model.create(Components.Schemas.AgentTokenCreate(kind: .music, scrobbler: scrobbler)) {
        case let .success(result): created = result
        case let .failure(failure): problem = failure.message ?? "The scrobbler could not be connected."
        }
    }

    private func copy(_ text: String) {
        Pasteboard.copy(text)
        copied = text
    }

    /// The token stays masked on screen; Copy takes it whole.
    static func masked(_ secret: String) -> String {
        "\(secret.prefix(8))••••••\(secret.suffix(3))"
    }

    /// Same list and text as the web's `lib/music/model.ts`.
    static func label(_ scrobbler: Scrobbler) -> String {
        switch scrobbler {
        case .webScrobbler: "Web Scrobbler"
        case .panoScrobbler: "Pano Scrobbler"
        case .navidrome: "Navidrome"
        case .jellyfin: "Jellyfin"
        case .other: "Other"
        }
    }

    static func summary(_ scrobbler: Scrobbler) -> String {
        switch scrobbler {
        case .webScrobbler:
            "A browser extension for Chrome, Firefox, Edge and Safari. Covers YouTube, YouTube Music, Spotify and "
                + "Apple Music in the browser."
        case .panoScrobbler:
            "An app for Android, Windows and Linux that sends whatever plays, Spotify and YouTube Music included."
        case .navidrome:
            "Your own music server. Plays in Navidrome and the apps connected to it are sent."
        case .jellyfin:
            "The ListenBrainz plugin sends what you play on your Jellyfin server."
        case .other:
            "Anything that lets you set its ListenBrainz server."
        }
    }
}
