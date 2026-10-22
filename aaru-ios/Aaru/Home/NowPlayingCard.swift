import AaruAPI
import SwiftUI

/// `NowPlayingCard` (DESIGN.md §15, SCR-008): what a player is playing now, above Tonight. Its
/// art, the episode, a bar where the player is, and "17m left", which a tap flips to
/// "Ends at 22:10". The clock runs on between polls while playing and stands still while paused.
/// Tapping the art or the title opens the title, as Tonight does.
struct NowPlayingCard: View {
    let playing: NowPlaying
    /// Side by side on wide screens with a larger art; the same order on a phone.
    var wide = false
    @State private var showsEndTime = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(playing.eyebrow).eyebrow()
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) {
                opening {
                    HStack(alignment: .center, spacing: wide ? 20 : 14) {
                        HomeArt(url: artURL, aspect: 16 / 9)
                            .frame(width: wide ? 220 : 128)
                            .clipShape(.rect(cornerRadius: 10, style: .continuous))
                        titles
                        Spacer(minLength: 0)
                    }
                }
                if playing.duration != nil {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        progress(at: context.date)
                    }
                    .padding(.top, 14)
                }
            }
            .padding(wide ? 20 : 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.surface))
            .clipShape(.rect(cornerRadius: 14, style: .continuous))
            .edgeLit()
        }
    }

    /// The title's link, when the player's title is on the shelf.
    @ViewBuilder
    private func opening(@ViewBuilder _ content: () -> some View) -> some View {
        if let id = playing.libraryItemId {
            NavigationLink(value: id) { content() }
                .buttonStyle(.plain)
                .accessibilityHint("Opens \(playing.title.title)")
        } else {
            content()
        }
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(playing.title.title)
                .font(.aaruDisplay(wide ? .title2 : .title3))
                .foregroundStyle(Color(.ink))
                .lineLimit(2)
            if let line = playing.episodeLine {
                Text(line)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Color(.muted))
                    .lineLimit(2)
            }
        }
    }

    private func progress(at date: Date) -> some View {
        HStack(spacing: 12) {
            ProgressView(value: playing.fraction(at: date) ?? 0)
                .tint(Color(.accent))
                .accessibilityLabel("Progress")
            Button {
                showsEndTime.toggle()
            } label: {
                Text(timeLabel(at: date))
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color(.accent))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // A paused player has no end time to show yet.
            .disabled(playing.state == .paused)
            .accessibilityHint(playing.state == .paused ? "" : "Shows the end time or the time left")
        }
    }

    /// "17m left", or "Ends at 22:10" once tapped.
    private func timeLabel(at date: Date) -> String {
        let left = playing.remaining(at: date) ?? 0
        if showsEndTime, playing.state == .playing {
            return "Ends at \(date.addingTimeInterval(left).formatted(date: .omitted, time: .shortened))"
        }
        return "\(durationLabel(minutes: Int((left / 60).rounded(.up)))) left"
    }

    private var artURL: URL? {
        (playing.title.backdropUrl ?? playing.title.posterUrl).flatMap(URL.init(string:))
    }
}

// MARK: Previews

extension NowPlaying {
    /// For previews: an episode 31 minutes into Stremio, playing or paused.
    static func sample(paused: Bool = false, libraryItemId: String? = UUID().uuidString) -> NowPlaying {
        .init(
            watchEventId: UUID().uuidString,
            libraryItemId: libraryItemId,
            title: .init(
                id: UUID().uuidString, _type: .show, title: "Severance", network: "Apple TV+", isAnime: false,
                ids: .init()
            ),
            episode: .init(season: 2, number: 7),
            episodeName: "Chikhai Bardo",
            source: .stremio,
            state: paused ? .paused : .playing,
            positionMs: 31 * 60000,
            durationMs: 48 * 60000,
            updatedAt: .now
        )
    }
}

#Preview("Now playing") {
    NavigationStack {
        VStack(spacing: 28) {
            NowPlayingCard(playing: .sample())
            NowPlayingCard(playing: .sample(paused: true))
        }
        .padding(20)
    }
}

#Preview("Now playing, wide · dark", traits: .fixedLayout(width: 900, height: 300)) {
    NavigationStack {
        NowPlayingCard(playing: .sample(), wide: true)
            .padding(20)
    }
    .preferredColorScheme(.dark)
}
