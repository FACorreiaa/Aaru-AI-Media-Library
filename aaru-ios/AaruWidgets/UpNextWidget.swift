import AppIntents
import SwiftUI
import WidgetKit

/// Up Next (WID-002): the next episode of each in-progress show, with a check that marks it
/// watched in place. Small: one; medium: three; large: five with progress.
struct UpNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AaruUpNext", provider: UpNextProvider()) { entry in
            UpNextView(entry: entry)
                .aaruWidgetBackground()
        }
        .configurationDisplayName("Up Next")
        .description("The next episode of every show you are watching. Check one off without opening Aaru.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct UpNextProvider: TimelineProvider {
    func placeholder(in _: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview ? .sample : WidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let deliver = Delivery(completion)
        let snapshot = WidgetSnapshotStore.load()
        let count = context.family == .systemLarge ? 5 : context.family == .systemMedium ? 3 : 1
        Task { @Sendable in
            var urls: [String: URL] = [:]
            for row in snapshot?.upNext.prefix(count) ?? [] {
                if let url = row.backdropURL ?? row.posterURL {
                    urls[row.libraryItemId] = url
                }
            }
            let artwork = await WidgetArtwork.fetch(urls)
            let entry = SnapshotEntry(date: .now, snapshot: snapshot, artwork: artwork)
            // Ticks and app loads reload this widget; the hourly refresh only catches a stale file.
            deliver.send(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(3600))))
        }
    }
}

/// WidgetKit's completion handler, carried into the task that fetches artwork. WidgetKit calls
/// `getTimeline` once per reload and the handler is called exactly once. Shared with Listening.
struct Delivery: @unchecked Sendable {
    let send: (Timeline<SnapshotEntry>) -> Void

    init(_ send: @escaping (Timeline<SnapshotEntry>) -> Void) {
        self.send = send
    }
}

struct UpNextView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var rows: [WidgetSnapshot.NextEpisode] {
        let all = entry.snapshot?.upNext ?? []
        switch family {
        case .systemSmall: return Array(all.prefix(1))
        case .systemMedium: return Array(all.prefix(3))
        default: return Array(all.prefix(5))
        }
    }

    var body: some View {
        if entry.snapshot == nil {
            SetUpView(compact: family == .systemSmall)
        } else if rows.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Up Next").font(.widgetDisplay).foregroundStyle(Palette.ink)
                Text("You are all caught up.").font(.caption).foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if family == .systemSmall, let row = rows.first {
            UpNextSmall(row: row, artwork: entry.artwork[row.libraryItemId])
        } else {
            VStack(alignment: .leading, spacing: family == .systemLarge ? 10 : 6) {
                Text("Up Next")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.brand)
                ForEach(rows) { row in
                    UpNextRow(row: row, artwork: entry.artwork[row.libraryItemId], showsDetail: family == .systemLarge)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// The check every row carries: runs the intent in place, without opening the app.
struct WatchedCheck: View {
    let row: WidgetSnapshot.NextEpisode

    var body: some View {
        Button(intent: MarkEpisodeWatchedIntent(
            libraryItemId: row.libraryItemId,
            season: row.season,
            episode: row.number
        )) {
            Image(systemName: "checkmark.circle")
                .font(.title3)
                .foregroundStyle(Palette.brand)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mark \(row.title) S\(row.season) E\(row.number) watched")
    }
}

private struct UpNextSmall: View {
    let row: WidgetSnapshot.NextEpisode
    let artwork: Data?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ArtworkView(data: artwork)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .clipShape(.rect(cornerRadius: 10))
            Text(row.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.brand)
                .lineLimit(1)
            Text("S\(row.season) · E\(row.number)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Palette.ink)
            HStack {
                Text(row.isFinale ? "Finale" : "\(row.remainingCount) left")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(row.isFinale ? Palette.gold : Palette.muted)
                Spacer()
                WatchedCheck(row: row)
            }
        }
        .widgetURL(WidgetLink.title(row.libraryItemId))
    }
}

private struct UpNextRow: View {
    let row: WidgetSnapshot.NextEpisode
    let artwork: Data?
    /// Large: episode name on the second line, "N left · time" on a third.
    let showsDetail: Bool

    var body: some View {
        HStack(spacing: 10) {
            Link(destination: WidgetLink.title(row.libraryItemId) ?? URL(fileURLWithPath: "/")) {
                HStack(spacing: 10) {
                    ArtworkView(data: artwork)
                        .frame(width: 64, height: 36)
                        .clipShape(.rect(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                        if showsDetail {
                            Text(remaining)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(row.isFinale ? Palette.gold : Palette.brand)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            WatchedCheck(row: row)
        }
    }

    /// "S2 · E8 · Sweet Vitriol"; on smaller rows the count goes here too.
    private var subtitle: String {
        var parts = ["S\(row.season) · E\(row.number)"]
        if showsDetail {
            if let name = row.episodeName {
                parts.append(name)
            }
        } else {
            parts.append(row.isFinale ? "Finale" : "\(row.remainingCount) left")
        }
        return parts.joined(separator: " · ")
    }

    /// "Finale · 1 left · 41m" or "4 left · 1h 36m".
    private var remaining: String {
        let count = "\(row.remainingCount) left · \(widgetDuration(minutes: row.remainingMinutes))"
        return row.isFinale ? "Finale · \(count)" : count
    }
}

#Preview(as: .systemMedium) {
    UpNextWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .sample)
    SnapshotEntry(date: .now, snapshot: nil)
}

#Preview(as: .systemLarge) {
    UpNextWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .sample)
}
