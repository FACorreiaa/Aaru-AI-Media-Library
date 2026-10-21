import AaruAPI
import SwiftUI

/// Connections → Music (MUS-007): scrobblers that send listens to Aaru. Shows the last listen as
/// the way to Listens (UX-016, UX-049), lists the scrobblers with last use, disconnects them, and
/// opens the sheet that connects one.
struct MusicSection: View {
    let model: ConnectionsModel
    /// Listens reads the log itself.
    let api: Client?

    @State private var connecting = false
    @State private var disconnecting: AgentToken?

    var body: some View {
        Section {
            if let latest = model.latestListen {
                NavigationLink {
                    MusicView(api: api)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Last listen: \(latest.track) — \(latest.artist)").foregroundStyle(Color(.ink))
                        ListenDetail(listen: latest).font(.caption).foregroundStyle(Color(.muted))
                        Text("All listens ›").font(.caption).foregroundStyle(Color(.accent))
                    }
                }
            }
            ForEach(model.scrobblers, id: \.id) { token in
                ConnectionRow(token: token, detail: ConnectionRow.lastUsed(token)) { disconnecting = token }
            }
            Button("Connect a scrobbler", systemImage: "music.note") { connecting = true }
                .disabled(!model.isAvailable)
        } header: {
            Text("Music")
        } footer: {
            Text(
                "Plays on YouTube, YouTube Music, Spotify and Apple Music in a browser, or any app on Android, land "
                    + "in Listens. The Spotify and Apple Music apps on iPhone can’t send plays."
            )
        }
        .confirmsDisconnect($disconnecting, stops: { _ in
            "It stops sending listens at once. Listens already in your log stay."
        }, perform: { token in
            Task { await model.disconnect(token) }
        })
        .sheet(isPresented: $connecting, onDismiss: { Task { await model.load() } }, content: {
            MusicSetupView(model: model, seen: model.latestListen)
        })
    }
}

/// "3 minutes ago · Web Scrobbler · YouTube Music": when, then what sent it and where it played.
struct ListenDetail: View {
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

