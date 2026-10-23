#if os(iOS)
    import AaruCore
    import ActivityKit
    import AppIntents
    import SwiftUI
    import WidgetKit

    // The pieces the Lock Screen rows and the Dynamic Island share (SCR-009).

    /// Opens the row's title when it is on the shelf; tracks and videos open nothing.
    struct RowLink<Content: View>: View {
        let item: NowPlayingActivityItem
        @ViewBuilder let content: Content

        var body: some View {
            if let url = item.libraryItemId.flatMap(WidgetLink.title) {
                Link(destination: url) { content }
            } else {
                content
            }
        }
    }

    /// "Ends at 1:20 PM" or a live "41m left" for an episode, movie or video, which a tap flips;
    /// the time left of a track. "Paused" (with what is left, in the long form) while paused,
    /// "Watched" once ticked, nothing without a duration.
    struct TimeLabel: View {
        let item: NowPlayingActivityItem
        let showsEndTime: Bool
        let long: Bool

        var body: some View {
            Group {
                if item.watched {
                    Label("Watched", systemImage: "checkmark")
                } else if let pausedAt = item.pausedAt {
                    if long, let endsAt = item.endsAt {
                        Text("Paused · \(leftLabel(endsAt.timeIntervalSince(pausedAt))) left")
                    } else {
                        Text("Paused")
                    }
                } else if let endsAt = item.endsAt {
                    if item.kind == .track {
                        Text(timerInterval: Date.now ... endsAt, countsDown: true, showsHours: false)
                    } else {
                        Button(intent: ToggleEndTimeIntent()) {
                            if showsEndTime {
                                Text(
                                    "\(long ? "Ends at" : "Ends") \(endsAt.formatted(date: .omitted, time: .shortened))"
                                )
                            } else {
                                Text(timerInterval: Date.now ... endsAt, countsDown: true, showsHours: true)
                                    + Text(" left")
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .foregroundStyle(Color(.accent))
        }
    }

    /// A bar that runs with the clock, or stands still at the pause. Needs `endsAt`. A standing
    /// bar is a capacity (elapsed over length), so it is a gauge; only the running one is a
    /// progress view, which is the one that can follow a timer.
    struct RowProgress: View {
        let item: NowPlayingActivityItem

        var body: some View {
            Group {
                if let endsAt = item.endsAt {
                    if let pausedAt = item.pausedAt {
                        let length = endsAt.timeIntervalSince(item.startedAt)
                        capacity(length > 0 ? min(max(pausedAt.timeIntervalSince(item.startedAt) / length, 0), 1) : 0)
                    } else if item.watched {
                        capacity(1)
                    } else {
                        ProgressView(
                            timerInterval: item.startedAt ... max(endsAt, item.startedAt),
                            countsDown: false,
                            label: { EmptyView() },
                            currentValueLabel: { EmptyView() }
                        )
                    }
                }
            }
            .tint(Color(.accent))
        }

        private func capacity(_ fraction: Double) -> some View {
            Gauge(value: fraction, in: 0 ... 1) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
        }
    }

    /// "17m", "1h 5m": what is left at the pause, rounded up to the minute.
    func leftLabel(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded(.up)))
        let (hours, rest) = (minutes / 60, minutes % 60)
        return hours == 0 ? "\(rest)m" : rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    /// Mark watched on an episode or a movie row that has not ticked: a full-width button for the
    /// lead alone, a check otherwise.
    struct MarkWatchedButton: View {
        let item: NowPlayingActivityItem
        let compact: Bool

        var body: some View {
            if let libraryItemId = item.libraryItemId, item.canMarkWatched {
                let intent = MarkNowPlayingWatchedIntent(
                    libraryItemId: libraryItemId, season: item.season, episode: item.episode
                )
                if compact {
                    Button(intent: intent) {
                        Image(systemName: "checkmark.circle")
                            .font(.title3)
                            .foregroundStyle(Color(.accent))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Mark watched")
                } else {
                    Button(intent: intent) {
                        Label("Mark watched", systemImage: "checkmark.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(.onAccent))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(.accent))
                }
            }
        }
    }

    /// The art the app saved into the App Group for this row, or the flat surface with the kind's
    /// glyph. Alone, a row keeps its art's shape (a poster, a cover, a thumbnail) at `height`;
    /// stacked, every row takes the same square so the titles line up.
    struct ArtTile: View {
        let item: NowPlayingActivityItem
        let size: CGSize

        nonisolated init(item: NowPlayingActivityItem, height: CGFloat) {
            self.item = item
            size = CGSize(width: height * item.kind.aspect, height: height)
        }

        nonisolated init(item: NowPlayingActivityItem, side: CGFloat) {
            self.item = item
            size = CGSize(width: side, height: side)
        }

        var body: some View {
            let artwork = NowPlayingArtwork.load(for: item.artworkURL)
            ArtworkView(data: artwork)
                .overlay {
                    if artwork == nil {
                        // The glyph is a share of the tile, which is a fixed frame, not text.
                        Image(systemName: item.kind.glyph)
                            .resizable()
                            .scaledToFit()
                            .frame(width: size.height * 0.4, height: size.height * 0.4)
                            .foregroundStyle(Color(.ink).opacity(AaruAlpha.half))
                    }
                }
                .frame(width: size.width, height: size.height)
                .accessibilityHidden(true)
        }
    }

    extension NowPlayingActivityItem {
        /// "S1 · E8 · Lanterns · Stremio", "Radiohead · YouTube Music".
        var detailLine: String {
            [subtitle, service].compactMap(\.self).joined(separator: " · ")
        }

        /// Episodes and movies on the shelf, not yet ticked.
        var canMarkWatched: Bool {
            (kind == .episode || kind == .movie) && libraryItemId != nil && !watched
        }
    }

    extension NowPlayingActivityItem.Kind {
        var glyph: String {
            switch self {
            case .episode: "tv"
            case .movie: "film"
            case .track: "music.note"
            case .video: "play.rectangle"
            }
        }

        /// Width over height of the art: a poster, a square cover, a 16:9 thumbnail.
        var aspect: CGFloat {
            switch self {
            case .episode, .movie: 2 / 3
            case .track: 1
            case .video: 16 / 9
            }
        }
    }
#endif
