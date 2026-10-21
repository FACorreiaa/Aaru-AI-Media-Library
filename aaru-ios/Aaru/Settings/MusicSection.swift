import AaruAPI
import SwiftUI

/// "Music" (MUS-007): scrobblers that send listens to Aaru (GET/POST/DELETE /v1/agent/tokens with
/// `for=music`). Shows the last listen, lists the scrobblers with last use, disconnects them, and
/// opens the sheet that connects one.
struct MusicSection: View {
    let api: Client?
    /// Shows a failure in Settings' problem banner.
    var onProblem: (String) -> Void

    @State private var tokens: [Components.Schemas.AgentToken] = []
    @State private var latest: Components.Schemas.Listen?
    @State private var loaded = false
    @State private var connecting = false
    @State private var revoking: Components.Schemas.AgentToken?

    var body: some View {
        Section {
            if !loaded, api != nil {
                ProgressView().frame(maxWidth: .infinity)
            }
            if let latest {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last listen: \(latest.track) — \(latest.artist)").foregroundStyle(Color(.ink))
                    ListenDetail(listen: latest).font(.caption).foregroundStyle(Color(.muted))
                }
            }
            ForEach(tokens, id: \.id) { token in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(token.name).foregroundStyle(Color(.ink))
                        lastUsed(token).font(.caption).foregroundStyle(Color(.muted))
                    }
                    Spacer()
                    Button("Disconnect", role: .destructive) { revoking = token }
                        .buttonStyle(.borderless)
                }
            }
            Button {
                connecting = true
            } label: {
                Label("Connect a scrobbler", systemImage: "music.note")
            }
            .disabled(api == nil)
        } header: {
            Text("Music")
        } footer: {
            Text(
                "Plays on YouTube, YouTube Music, Spotify and Apple Music in a browser, or any app on Android, land "
                    + "in your listening log. The Spotify and Apple Music apps on iPhone can’t send plays."
            )
        }
        .confirmationDialog(
            "Disconnect \(revoking?.name ?? "this scrobbler")?",
            isPresented: Binding(get: { revoking != nil }, set: {
                if !$0 {
                    revoking = nil
                }
            }),
            titleVisibility: .visible,
            presenting: revoking
        ) { token in
            Button("Disconnect", role: .destructive) { Task { await revoke(token) } }
        } message: { _ in
            Text("It stops sending listens at once. Listens already in your log stay.")
        }
        .sheet(isPresented: $connecting, onDismiss: { Task { await load() } }, content: {
            if let api {
                MusicSetupView(api: api, seen: latest) { created in
                    tokens.insert(created.token, at: 0)
                }
            }
        })
        .task { await load() }
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
            switch try await api.listAgentTokens(query: .init(_for: .music)) {
            case let .ok(response):
                tokens = try response.body.json.items.filter { $0.kind == .music }
            case let .default(_, error):
                onProblem((try? error.body.json.message) ?? "Your scrobblers could not be loaded.")
            }
        } catch {
            onProblem("Your scrobblers could not be loaded. Aaru could not reach the server.")
        }
        // The last listen is a nicety; nothing is reported when it fails.
        latest = await MusicSetupView.latestListen(api)
    }

    private func revoke(_ token: Components.Schemas.AgentToken) async {
        guard let api else { return }
        do {
            switch try await api.revokeAgentToken(path: .init(id: token.id)) {
            case .noContent:
                tokens.removeAll { $0.id == token.id }
            case let .default(_, error):
                onProblem((try? error.body.json.message) ?? "That scrobbler was not disconnected.")
            }
        } catch {
            onProblem("That scrobbler was not disconnected. Aaru could not reach the server.")
        }
    }
}

/// "3 minutes ago · Web Scrobbler · YouTube Music": when, then what sent it and where it played.
private struct ListenDetail: View {
    let listen: Components.Schemas.Listen

    var body: some View {
        let sources = [listen.client, listen.musicService].compactMap(\.self)
        if sources.isEmpty {
            Text(listen.listenedAt, format: .relative(presentation: .named))
        } else {
            Text("\(listen.listenedAt, format: .relative(presentation: .named)) · \(sources.joined(separator: " · "))")
        }
    }
}

/// Connect one scrobbler: pick it, connect, and the server answers its steps with the token
/// filled in, shown once. Then the sheet waits for the first listen so the user knows it works.
struct MusicSetupView: View {
    typealias Scrobbler = Components.Schemas.MusicScrobbler

    let api: Client
    /// The newest listen when the sheet opened; any other one is the scrobbler's first.
    let seen: Components.Schemas.Listen?
    var onCreated: (Components.Schemas.AgentTokenCreated) -> Void

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
                    Section { Text(problem).foregroundStyle(.red) }
                }
            }
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
            if let listen = await Self.latestListen(api), listen.id != seen?.id {
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
        let body = Components.Schemas.AgentTokenCreate(kind: .music, scrobbler: scrobbler)
        do {
            switch try await api.createAgentToken(body: .json(body)) {
            case let .created(response):
                let result = try response.body.json
                created = result
                onCreated(result)
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "The scrobbler could not be connected."
            }
        } catch {
            problem = "The scrobbler could not be connected. Aaru could not reach the server."
        }
    }

    private func copy(_ text: String) {
        #if os(iOS)
            UIPasteboard.general.string = text
        #elseif os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        #endif
        copied = text
    }

    /// The newest listen, or nil before the first one or when it could not be loaded.
    static func latestListen(_ api: Client) async -> Components.Schemas.Listen? {
        guard case let .ok(response) = try? await api.listListens(query: .init(limit: 1)) else { return nil }
        return try? response.body.json.items.first
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
