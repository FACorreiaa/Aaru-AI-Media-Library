#if os(iOS)
    import AaruCore
    import ActivityKit
    import AppIntents
    import SwiftUI
    import WidgetKit

    /// "Now playing" in the Dynamic Island (SCR-009). Compact: the lead's art, then the second
    /// row's glyph, or the lead's time when it plays alone. Minimal: the lead's glyph. Expanded:
    /// the lead large, its bar and check, then up to two more rows.
    enum NowPlayingIsland {
        static func make(_ state: NowPlayingActivityState) -> DynamicIsland {
            let primary = state.items.first
            let others = Array(state.items.dropFirst().prefix(NowPlayingActivityState.maxItems - 1))
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if let primary {
                        ArtTile(item: primary, height: 52)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    if let primary {
                        IslandHeadline(item: primary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let primary {
                        TimeLabel(item: primary, showsEndTime: state.showsEndTime, long: false)
                            .font(.caption.weight(.semibold))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandBottom(primary: primary, others: others, showsEndTime: state.showsEndTime)
                }
            } compactLeading: {
                if let primary {
                    ArtTile(item: primary, side: 22)
                }
            } compactTrailing: {
                CompactTrailing(primary: primary, others: others)
            } minimal: {
                if let primary {
                    Image(systemName: primary.watched ? "checkmark" : primary.kind.glyph)
                        .foregroundStyle(Color(.accent))
                }
            }
            .widgetURL(nowPlayingLink(state))
            .keylineTint(Color(.accent))
        }
    }

    /// The lead's title and its line, beside its art.
    private struct IslandHeadline: View {
        let item: NowPlayingActivityItem

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(item.detailLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The lead's bar and check, then the other rows.
    private struct IslandBottom: View {
        let primary: NowPlayingActivityItem?
        let others: [NowPlayingActivityItem]
        let showsEndTime: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                if let primary, primary.endsAt != nil || primary.canMarkWatched {
                    HStack(spacing: 12) {
                        if primary.endsAt != nil {
                            RowProgress(item: primary)
                        } else {
                            Spacer(minLength: 0)
                        }
                        MarkWatchedButton(item: primary, compact: true)
                    }
                }
                ForEach(others) { item in
                    IslandRow(item: item, showsEndTime: showsEndTime)
                }
            }
        }
    }

    /// The second row's glyph when more than one plays, else the lead's time.
    private struct CompactTrailing: View {
        let primary: NowPlayingActivityItem?
        let others: [NowPlayingActivityItem]

        var body: some View {
            if let second = others.first {
                Image(systemName: second.kind.glyph)
                    .foregroundStyle(Color(.accent))
                    .accessibilityLabel(others.count == 1 ? "And one more" : "And \(others.count) more")
            } else if let primary {
                CompactTime(item: primary)
            }
        }
    }

    /// A row under the lead in the expanded island: small art, the title and its line, its time.
    private struct IslandRow: View {
        let item: NowPlayingActivityItem
        let showsEndTime: Bool

        var body: some View {
            RowLink(item: item) {
                HStack(spacing: 8) {
                    ArtTile(item: item, side: 24)
                    Text(item.title)
                        .font(.caption.weight(.semibold))
                        + Text(item.subtitle.map { "  \($0)" } ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    TimeLabel(item: item, showsEndTime: showsEndTime, long: false)
                        .font(.caption2.weight(.semibold))
                }
                .lineLimit(1)
            }
        }
    }

    /// The compact island's trailing side with one item: its time left, or a pause or a check.
    private struct CompactTime: View {
        let item: NowPlayingActivityItem

        var body: some View {
            if item.watched {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color(.accent))
                    .accessibilityLabel("Watched")
            } else if item.pausedAt != nil {
                Image(systemName: "pause.fill")
                    .foregroundStyle(Color(.accent))
                    .accessibilityLabel("Paused")
            } else if let endsAt = item.endsAt {
                Text(timerInterval: Date.now ... endsAt, countsDown: true, showsHours: false)
                    .monospacedDigit()
                    .frame(maxWidth: 44)
                    .foregroundStyle(Color(.accent))
            } else {
                Image(systemName: item.kind.glyph)
                    .foregroundStyle(Color(.accent))
            }
        }
    }
#endif
