#if os(iOS)
    import AaruCore
    import ActivityKit
    import AppIntents
    import SwiftUI
    import WidgetKit

    /// "Now playing" (SCR-009, `NowPlayingCard`): Lock Screen, banner and Dynamic Island for
    /// everything playing at once, up to three rows of episodes, movies, tracks and videos. One
    /// item leads in full; two or three stack as compact rows. Clocks and bars run from the
    /// state's dates, so they move without a push; a paused row stands still. Art the app has not
    /// saved yet draws as its kind's glyph.
    struct NowPlayingLiveActivity: Widget {
        var body: some WidgetConfiguration {
            ActivityConfiguration(for: NowPlayingActivityAttributes.self) { context in
                NowPlayingLockScreen(state: context.state, isStale: context.isStale)
                    .activityBackgroundTint(Color(.paper))
                    .activitySystemActionForegroundColor(Color(.ink))
                    .widgetURL(nowPlayingLink(context.state))
            } dynamicIsland: { context in
                NowPlayingIsland.make(context.state)
            }
        }
    }

    /// "Now watching" (WID-005): the episode started by hand, drawn by the same renderer as one
    /// row.
    struct NowWatchingLiveActivity: Widget {
        var body: some WidgetConfiguration {
            ActivityConfiguration(for: NowWatchingAttributes.self) { context in
                let state = context.attributes.activityState(context.state)
                NowPlayingLockScreen(state: state, isStale: context.isStale)
                    .activityBackgroundTint(Color(.paper))
                    .activitySystemActionForegroundColor(Color(.ink))
                    .widgetURL(nowPlayingLink(state))
            } dynamicIsland: { context in
                NowPlayingIsland.make(context.attributes.activityState(context.state))
            }
        }
    }

    /// The lead row's title, when it is on the shelf; otherwise the app opens as it was.
    func nowPlayingLink(_ state: NowPlayingActivityState) -> URL? {
        state.items.first?.libraryItemId.flatMap(WidgetLink.title)
    }

    struct NowPlayingLockScreen: View {
        let state: NowPlayingActivityState
        let isStale: Bool

        var body: some View {
            let items = Array(state.items.prefix(NowPlayingActivityState.maxItems))
            if items.count == 1, let item = items.first {
                LeadRow(item: item, showsEndTime: state.showsEndTime, isStale: isStale)
                    .padding(16)
            } else if items.isEmpty {
                Text("Nothing playing")
                    .font(.subheadline)
                    .foregroundStyle(Color(.muted))
                    .padding(16)
            } else {
                // A check column for every row once one row has a check, so the times line up.
                let reservesCheck = items.contains(where: \.canMarkWatched)
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        StackedRow(item: item, showsEndTime: state.showsEndTime, reservesCheck: reservesCheck)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    /// One item alone: the art at full height, the title in the display style, its line, a bar where the
    /// player is, and Mark watched for an episode or a movie.
    struct LeadRow: View {
        let item: NowPlayingActivityItem
        let showsEndTime: Bool
        let isStale: Bool

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                ArtTile(item: item, height: 64)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.title)
                            .font(.widgetDisplay)
                            .foregroundStyle(Color(.ink))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        TimeLabel(item: item, showsEndTime: showsEndTime, long: true)
                            .font(.caption.weight(.semibold))
                    }
                    if !item.detailLine.isEmpty {
                        Text(item.detailLine)
                            .font(.caption)
                            .foregroundStyle(Color(.muted))
                            .lineLimit(1)
                    }
                    if isStale, item.canMarkWatched {
                        Text("Did you finish?")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(.ink))
                    } else if item.endsAt != nil {
                        RowProgress(item: item)
                    }
                    MarkWatchedButton(item: item, compact: false)
                }
            }
        }
    }

    /// One of two or three: a square of art, the title and its time left, then its line with a
    /// short bar under the time, and a check for an episode or a movie.
    struct StackedRow: View {
        let item: NowPlayingActivityItem
        let showsEndTime: Bool
        let reservesCheck: Bool

        var body: some View {
            HStack(spacing: 12) {
                RowLink(item: item) {
                    HStack(spacing: 12) {
                        ArtTile(item: item, side: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color(.ink))
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                TimeLabel(item: item, showsEndTime: showsEndTime, long: false)
                                    .font(.caption.weight(.semibold))
                            }
                            HStack(spacing: 8) {
                                Text(item.detailLine)
                                    .font(.caption)
                                    .foregroundStyle(Color(.muted))
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                if item.endsAt != nil, !item.watched {
                                    RowProgress(item: item)
                                        .frame(width: 64)
                                }
                            }
                        }
                    }
                }
                if item.canMarkWatched {
                    MarkWatchedButton(item: item, compact: true)
                } else if reservesCheck {
                    Color.clear.frame(width: 28, height: 28)
                }
            }
        }
    }
#endif
