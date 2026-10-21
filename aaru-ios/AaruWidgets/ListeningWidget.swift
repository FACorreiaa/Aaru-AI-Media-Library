import SwiftUI
import WidgetKit

/// Listening (MUS-001): square covers of the albums marked Listening, most recently touched
/// first. Small: one, with its name and artist; medium: four. A cover opens the album.
struct ListeningWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AaruListening", provider: ListeningProvider()) { entry in
            ListeningView(entry: entry)
                .aaruWidgetBackground()
        }
        .configurationDisplayName("Listening")
        .description("The albums you are listening to.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ListeningProvider: TimelineProvider {
    func placeholder(in _: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .sample : WidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let deliver = Delivery(completion)
        let snapshot = WidgetSnapshotStore.load()
        let count = ListeningView.capacity(context.family)
        Task { @Sendable in
            var urls: [String: URL] = [:]
            for album in snapshot?.listening?.prefix(count) ?? [] {
                if let url = album.coverURL {
                    urls[album.libraryItemId] = url
                }
            }
            let artwork = await WidgetArtwork.fetch(urls, maxPixel: 300)
            let entry = SnapshotEntry(date: .now, snapshot: snapshot, artwork: artwork)
            // Nothing here changes with time: the app reloads this widget whenever it writes the
            // snapshot. The slow refresh only retries covers that did not load.
            deliver.send(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(6 * 3600))))
        }
    }
}

struct ListeningView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    /// Covers each family shows.
    nonisolated static func capacity(_ family: WidgetFamily) -> Int {
        family == .systemSmall ? 1 : 4
    }

    private var albums: [WidgetSnapshot.Album] {
        Array((entry.snapshot?.listening ?? []).prefix(Self.capacity(family)))
    }

    var body: some View {
        if entry.snapshot == nil {
            SetUpView(compact: family == .systemSmall)
        } else if albums.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Listening").font(.widgetDisplay).foregroundStyle(Palette.ink)
                Text("Albums you mark Listening show here.").font(.caption).foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if family == .systemSmall, let album = albums.first {
            ListeningSmall(album: album, artwork: entry.artwork[album.libraryItemId])
        } else {
            ListeningMedium(
                albums: albums,
                total: entry.snapshot?.listening?.count ?? albums.count,
                artwork: entry.artwork
            )
        }
    }
}

/// A square cover at whatever width it is given, rounded like the app's covers.
private struct Cover: View {
    let data: Data?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { ArtworkView(data: data) }
            .clipShape(.rect(cornerRadius: 8))
            .accessibilityHidden(true)
    }
}

private struct ListeningSmall: View {
    let album: WidgetSnapshot.Album
    let artwork: Data?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Cover(data: artwork)
                    .frame(width: 72)
                Spacer(minLength: 0)
                Image(systemName: "music.note")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.brand)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 0) {
                Text(album.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if let artist = album.artist {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .widgetURL(WidgetLink.title(album.libraryItemId))
    }
}

private struct ListeningMedium: View {
    let albums: [WidgetSnapshot.Album]
    /// Every album in progress, for "6 albums" when there are more than fit.
    let total: Int
    let artwork: [String: Data]

    private static let slots = ListeningView.capacity(.systemMedium)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Listening")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.brand)
                Spacer()
                if total > albums.count {
                    Text("\(total) albums")
                        .font(.caption2)
                        .foregroundStyle(Palette.muted)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                ForEach(0 ..< Self.slots, id: \.self) { slot in
                    if albums.indices.contains(slot) {
                        AlbumLink(album: albums[slot], artwork: artwork[albums[slot].libraryItemId])
                    } else {
                        // Empty slots keep every cover the same size.
                        Color.clear.aspectRatio(1, contentMode: .fit)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct AlbumLink: View {
    let album: WidgetSnapshot.Album
    let artwork: Data?

    var body: some View {
        Link(destination: WidgetLink.title(album.libraryItemId) ?? URL(fileURLWithPath: "/")) {
            VStack(alignment: .leading, spacing: 4) {
                Cover(data: artwork)
                Text(album.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
            }
        }
        .accessibilityLabel([album.title, album.artist].compactMap(\.self).joined(separator: ", "))
    }
}

#Preview(as: .systemSmall) {
    ListeningWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .sample)
    SnapshotEntry(date: .now, snapshot: nil)
}

#Preview(as: .systemMedium) {
    ListeningWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .sample)
    SnapshotEntry(date: .now, snapshot: WidgetSnapshot(upNext: [], airings: [], listening: [], writtenAt: .now))
}
