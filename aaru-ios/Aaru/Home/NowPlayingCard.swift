import AaruAPI
import SwiftUI

/// `NowPlayingCard` (DESIGN.md §15, SCR-008, SCR-009): everything playing now, above Tonight, in
/// the Live Activity's order. The first item leads in full: its art, the episode, a bar where the
/// player is, and "17m left", which a tap flips to "Ends at 22:10". The others follow as compact
/// rows with their own time left. Clocks run on between polls while playing and stand still while
/// paused. Tapping a library item opens the title, as Tonight does.
struct NowPlayingCard: View {
    let items: [NowPlayingItem]
    /// Side by side on wide screens with a larger art; the same order on a phone.
    var wide = false
    @State private var showsEndTime = false

    var body: some View {
        if let primary = items.first {
            VStack(alignment: .leading, spacing: 12) {
                Text(primary.eyebrow).eyebrow()
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 0) {
                    NowPlayingLink(item: primary) {
                        HStack(alignment: .center, spacing: wide ? 20 : 14) {
                            HomeArt(url: artURL(primary), aspect: artAspect(primary))
                                .frame(width: artWidth(primary))
                                .clipShape(.rect(cornerRadius: AaruRadius.field, style: .continuous))
                            titles(primary)
                            Spacer(minLength: 0)
                        }
                    }
                    if primary.duration != nil {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            progress(primary, at: context.date)
                        }
                        .padding(.top, AaruSpace.large)
                    }
                    ForEach(items.dropFirst(), id: \.id) { item in
                        Divider()
                            .padding(.vertical, 12)
                        NowPlayingRow(item: item)
                    }
                }
                .panel(padding: wide ? AaruSpace.xlarge : AaruSpace.large)
                .edgeLit()
            }
        }
    }

    private func titles(_ item: NowPlayingItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .font(.aaruDisplay(wide ? .title2 : .title3))
                .foregroundStyle(Color(.ink))
                .lineLimit(2)
            if let line = item.subtitle {
                Text(line)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Color(.muted))
                    .lineLimit(2)
            }
        }
    }

    private func progress(_ item: NowPlayingItem, at date: Date) -> some View {
        HStack(spacing: 12) {
            ProgressView(value: item.fraction(at: date) ?? 0)
                .accessibilityLabel("Progress")
            Button {
                showsEndTime.toggle()
            } label: {
                Text(timeLabel(item, at: date))
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color(.accent))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // A paused player has no end time to show yet.
            .disabled(item.state == .paused)
            .accessibilityHint(item.state == .paused ? "" : "Shows the end time or the time left")
        }
    }

    /// "17m left", or "Ends at 22:10" once tapped.
    private func timeLabel(_ item: NowPlayingItem, at date: Date) -> String {
        let left = item.remaining(at: date) ?? 0
        if showsEndTime, item.state == .playing {
            return "Ends at \(date.addingTimeInterval(left).formatted(date: .omitted, time: .shortened))"
        }
        return "\(durationLabel(minutes: Int((left / 60).rounded(.up)))) left"
    }

    /// A film or show leads with its backdrop, a video with its thumbnail, a track with its
    /// square cover.
    private func artURL(_ item: NowPlayingItem) -> URL? {
        let backdrop = item.kind == .episode || item.kind == .movie ? item.title?.backdropUrl : nil
        return (backdrop ?? item.artURL).flatMap(URL.init(string:))
    }

    private func artAspect(_ item: NowPlayingItem) -> CGFloat {
        item.kind == .track ? 1 : 16 / 9
    }

    private func artWidth(_ item: NowPlayingItem) -> CGFloat {
        item.kind == .track ? (wide ? 124 : 72) : (wide ? 220 : 128)
    }
}

/// One more thing playing, under the lead: a square of its art, the name, "artist · Spotify" or
/// "S1 · E8 · Netflix", and its time left, or "Paused".
private struct NowPlayingRow: View {
    let item: NowPlayingItem

    var body: some View {
        NowPlayingLink(item: item) {
            HStack(spacing: 12) {
                HomeArt(url: item.artURL.flatMap(URL.init(string:)), aspect: 1)
                    .frame(width: 40)
                    .clipShape(.rect(cornerRadius: AaruRadius.thumb, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(.ink))
                        .lineLimit(1)
                    Text([item.subtitle, item.serviceName].compactMap(\.self).joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(Color(.muted))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    if let label = trailing(at: context.date) {
                        Text(label)
                            .font(.footnote.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color(.accent))
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func trailing(at date: Date) -> String? {
        if item.state == .paused {
            return "Paused"
        }
        return item.remaining(at: date).map { "\(durationLabel(minutes: Int(($0 / 60).rounded(.up)))) left" }
    }
}

/// The title's link, when the item is on the shelf; tracks and videos are not.
private struct NowPlayingLink<Content: View>: View {
    let item: NowPlayingItem
    @ViewBuilder let content: Content

    var body: some View {
        if let id = item.libraryItemId {
            NavigationLink(value: id) { content }
                .buttonStyle(.plain)
                .accessibilityHint("Opens \(item.name)")
        } else {
            content
        }
    }
}

// MARK: Previews

extension NowPlayingItem {
    /// For previews: an episode 31 minutes into Stremio, playing or paused.
    static func sample(paused: Bool = false, libraryItemId: String? = UUID().uuidString) -> NowPlayingItem {
        .init(
            id: UUID().uuidString,
            kind: .episode,
            name: "Severance",
            subtitle: "S2 · E7 · Chikhai Bardo",
            service: "Stremio",
            source: .stremio,
            state: paused ? .paused : .playing,
            positionMs: 31 * 60000,
            durationMs: 48 * 60000,
            updatedAt: .now,
            libraryItemId: libraryItemId,
            title: .init(
                id: UUID().uuidString, _type: .show, title: "Severance", network: "Apple TV+", isAnime: false,
                ids: .init()
            ),
            episode: .init(season: 2, number: 7)
        )
    }

    /// For previews: a track a minute in, from Web Scrobbler.
    static var sampleTrack: NowPlayingItem {
        .init(
            id: UUID().uuidString, kind: .track, name: "Everything In Its Right Place", subtitle: "Radiohead",
            service: "YouTube Music", source: .listenbrainz, state: .playing, positionMs: 0,
            durationMs: 251_000, updatedAt: .now.addingTimeInterval(-60)
        )
    }

    /// For previews: a YouTube video, paused.
    static var sampleVideo: NowPlayingItem {
        .init(
            id: UUID().uuidString, kind: .video, name: "How the Field of Reeds was mapped",
            subtitle: "Egyptology Today", service: "YouTube", source: .youtube, state: .paused,
            positionMs: 4 * 60000, durationMs: 19 * 60000, updatedAt: .now
        )
    }
}

#Preview("Now playing") {
    NavigationStack {
        ScrollView {
            VStack(spacing: AaruSpace.section) {
                NowPlayingCard(items: [.sample()])
                NowPlayingCard(items: [.sample(paused: true)])
                NowPlayingCard(items: [.sample(), .sampleVideo, .sampleTrack])
                NowPlayingCard(items: [.sampleTrack])
            }
            .padding(20)
        }
    }
}

#Preview("Now playing, wide · dark", traits: .fixedLayout(width: 900, height: 420)) {
    NavigationStack {
        NowPlayingCard(items: [.sample(), .sampleTrack], wide: true)
            .padding(20)
    }
    .preferredColorScheme(.dark)
}
