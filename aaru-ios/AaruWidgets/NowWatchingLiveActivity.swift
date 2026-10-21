#if os(iOS)
    import ActivityKit
    import AppIntents
    import SwiftUI
    import WidgetKit

    /// "Now watching" (WID-005, `NowPlayingCard`): Lock Screen, banner and Dynamic Island.
    struct NowWatchingLiveActivity: Widget {
        var body: some WidgetConfiguration {
            ActivityConfiguration(for: NowWatchingAttributes.self) { context in
                NowWatchingLockScreen(context: context)
                    .activityBackgroundTint(Palette.paper)
                    .activitySystemActionForegroundColor(Palette.ink)
                    .widgetURL(WidgetLink.title(context.attributes.libraryItemId))
            } dynamicIsland: { context in
                DynamicIsland {
                    DynamicIslandExpandedRegion(.leading) {
                        NowWatchingPoster(size: 52)
                    }
                    DynamicIslandExpandedRegion(.center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.attributes.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(context.attributes.episodeLine)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    DynamicIslandExpandedRegion(.trailing) {
                        TimeLabel(state: context.state)
                            .font(.caption.weight(.semibold))
                    }
                    DynamicIslandExpandedRegion(.bottom) {
                        VStack(spacing: 8) {
                            NowWatchingProgress(state: context.state)
                            MarkWatchedButton(attributes: context.attributes, state: context.state)
                        }
                    }
                } compactLeading: {
                    NowWatchingPoster(size: 22)
                        .clipShape(Circle())
                } compactTrailing: {
                    if context.state.watched {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Palette.brand)
                    } else {
                        Text(timerInterval: Date.now ... context.state.endsAt, countsDown: true, showsHours: false)
                            .monospacedDigit()
                            .frame(maxWidth: 44)
                            .foregroundStyle(Palette.brand)
                    }
                } minimal: {
                    ProgressView(
                        timerInterval: context.state.startedAt ... context.state.endsAt,
                        countsDown: false,
                        label: { EmptyView() },
                        currentValueLabel: { EmptyView() }
                    )
                    .progressViewStyle(.circular)
                    .tint(Palette.brand)
                }
                .widgetURL(WidgetLink.title(context.attributes.libraryItemId))
                .keylineTint(Palette.brand)
            }
        }
    }

    private struct NowWatchingLockScreen: View {
        let context: ActivityViewContext<NowWatchingAttributes>

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                NowWatchingPoster(size: 64)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(context.attributes.title)
                            .font(.widgetDisplay)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        TimeLabel(state: context.state)
                            .font(.caption.weight(.semibold))
                    }
                    Text(context.attributes.episodeLine)
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                    if context.isStale, !context.state.watched {
                        Text("Did you finish?")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                    } else {
                        NowWatchingProgress(state: context.state)
                    }
                    MarkWatchedButton(attributes: context.attributes, state: context.state)
                }
            }
            .padding(14)
        }
    }

    /// "Ends at 1:20 PM" or a live "41m left"; tapping flips it. "Watched" once ticked.
    private struct TimeLabel: View {
        let state: NowWatchingAttributes.ContentState

        var body: some View {
            if state.watched {
                Label("Watched", systemImage: "checkmark")
                    .foregroundStyle(Palette.brand)
            } else {
                Button(intent: ToggleEndTimeIntent()) {
                    Group {
                        if state.showsEndTime {
                            Text("Ends at \(state.endsAt.formatted(date: .omitted, time: .shortened))")
                        } else {
                            Text(timerInterval: Date.now ... state.endsAt, countsDown: true, showsHours: true)
                                .monospacedDigit() + Text(" left")
                        }
                    }
                    .foregroundStyle(Palette.brand)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private struct NowWatchingProgress: View {
        let state: NowWatchingAttributes.ContentState

        var body: some View {
            ProgressView(
                timerInterval: state.startedAt ... state.endsAt,
                countsDown: false,
                label: { EmptyView() },
                currentValueLabel: { EmptyView() }
            )
            .tint(Palette.brand)
        }
    }

    private struct MarkWatchedButton: View {
        let attributes: NowWatchingAttributes
        let state: NowWatchingAttributes.ContentState

        var body: some View {
            if !state.watched {
                Button(intent: MarkNowWatchingIntent(
                    libraryItemId: attributes.libraryItemId, season: attributes.season, episode: attributes.episode
                )) {
                    Label("Mark watched", systemImage: "checkmark.circle")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.brand)
            }
        }
    }

    /// The poster the app saved into the App Group when the activity started, or the brand wash.
    private struct NowWatchingPoster: View {
        let size: CGFloat

        var body: some View {
            ArtworkView(data: NowWatchingArtwork.load())
                .frame(width: size * 2 / 3, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size / 8))
        }
    }

    private extension NowWatchingAttributes {
        static let preview = NowWatchingAttributes(
            libraryItemId: "preview", title: "Andor", season: 2, episode: 8, episodeName: "Who Are You?",
            posterURL: nil, runtimeMinutes: 48
        )
    }

    private extension NowWatchingAttributes.ContentState {
        static func sample(endTime: Bool, watched: Bool = false, startedMinutesAgo: Double = 7) -> Self {
            let start = Date.now.addingTimeInterval(-startedMinutesAgo * 60)
            return .init(
                startedAt: start, endsAt: start.addingTimeInterval(48 * 60), showsEndTime: endTime, watched: watched
            )
        }
    }

    #Preview("Lock Screen", as: .content, using: NowWatchingAttributes.preview) {
        NowWatchingLiveActivity()
    } contentStates: {
        NowWatchingAttributes.ContentState.sample(endTime: true)
        NowWatchingAttributes.ContentState.sample(endTime: false)
        NowWatchingAttributes.ContentState.sample(endTime: true, startedMinutesAgo: 90)
        NowWatchingAttributes.ContentState.sample(endTime: false, watched: true)
    }

    #Preview("Island compact", as: .dynamicIsland(.compact), using: NowWatchingAttributes.preview) {
        NowWatchingLiveActivity()
    } contentStates: {
        NowWatchingAttributes.ContentState.sample(endTime: false)
    }

    #Preview("Island expanded", as: .dynamicIsland(.expanded), using: NowWatchingAttributes.preview) {
        NowWatchingLiveActivity()
    } contentStates: {
        NowWatchingAttributes.ContentState.sample(endTime: true)
    }

    #Preview("Island minimal", as: .dynamicIsland(.minimal), using: NowWatchingAttributes.preview) {
        NowWatchingLiveActivity()
    } contentStates: {
        NowWatchingAttributes.ContentState.sample(endTime: false)
    }
#endif
