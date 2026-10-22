#if os(iOS)
    import AaruCore
    import ActivityKit
    import AppIntents
    import SwiftUI
    import WidgetKit

    /// "Now watching" (WID-005, SCR-008, `NowPlayingCard`): Lock Screen, banner and Dynamic Island.
    /// While the player is paused the progress stands still; one the server started by push has no
    /// poster until the app has stored it, and draws without one.
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
                        NowWatchingPoster(attributes: context.attributes, state: context.state, size: 52)
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
                    NowWatchingPoster(attributes: context.attributes, state: context.state, size: 22)
                        .clipShape(Circle())
                } compactTrailing: {
                    if context.state.watched {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Palette.brand)
                    } else if context.state.pausedAt != nil {
                        Image(systemName: "pause.fill")
                            .foregroundStyle(Palette.brand)
                            .accessibilityLabel("Paused")
                    } else {
                        Text(timerInterval: Date.now ... context.state.endsAt, countsDown: true, showsHours: false)
                            .monospacedDigit()
                            .frame(maxWidth: 44)
                            .foregroundStyle(Palette.brand)
                    }
                } minimal: {
                    NowWatchingProgress(state: context.state)
                        .progressViewStyle(.circular)
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
                // Title-only until the app has stored the poster: no empty frame on the Lock Screen.
                if NowWatchingArtwork.load(for: context.attributes.posterURL) != nil {
                    NowWatchingPoster(attributes: context.attributes, state: context.state, size: 64)
                }
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

    /// "Ends at 1:20 PM" or a live "41m left"; tapping flips it. "Paused · 17m left" while the
    /// player is paused, "Watched" once ticked.
    private struct TimeLabel: View {
        let state: NowWatchingContent

        var body: some View {
            if state.watched {
                Label("Watched", systemImage: "checkmark")
                    .foregroundStyle(Palette.brand)
            } else if let pausedAt = state.pausedAt {
                Text("Paused · \(leftLabel(state.endsAt.timeIntervalSince(pausedAt))) left")
                    .monospacedDigit()
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

    /// A bar that runs with the clock, or stands still at the pause.
    private struct NowWatchingProgress: View {
        let state: NowWatchingContent

        var body: some View {
            Group {
                if let pausedAt = state.pausedAt {
                    let length = state.endsAt.timeIntervalSince(state.startedAt)
                    ProgressView(
                        value: length > 0 ? min(max(pausedAt.timeIntervalSince(state.startedAt) / length, 0), 1) : 0
                    )
                } else {
                    ProgressView(
                        timerInterval: state.startedAt ... state.endsAt,
                        countsDown: false,
                        label: { EmptyView() },
                        currentValueLabel: { EmptyView() }
                    )
                }
            }
            .tint(Palette.brand)
        }
    }

    /// "17m", "1h 5m": what is left at the pause, rounded up to the minute.
    private func leftLabel(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded(.up)))
        let (hours, rest) = (minutes / 60, minutes % 60)
        return hours == 0 ? "\(rest)m" : rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    private struct MarkWatchedButton: View {
        let attributes: NowWatchingAttributes
        let state: NowWatchingContent

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

    /// The poster the app saved into the App Group for this activity, or the brand wash with a
    /// play or pause glyph.
    private struct NowWatchingPoster: View {
        let attributes: NowWatchingAttributes
        let state: NowWatchingContent
        let size: CGFloat

        var body: some View {
            let artwork = NowWatchingArtwork.load(for: attributes.posterURL)
            ArtworkView(data: artwork)
                .overlay {
                    if artwork == nil {
                        Image(systemName: state.pausedAt == nil ? "play.fill" : "pause.fill")
                            .font(.system(size: size / 3))
                            .foregroundStyle(Palette.ink.opacity(0.6))
                    }
                }
                .frame(width: size * 2 / 3, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size / 8))
                .accessibilityHidden(true)
        }
    }

    private extension NowWatchingAttributes {
        static let preview = NowWatchingAttributes(
            libraryItemId: "preview", title: "Andor", season: 2, episode: 8, episodeName: "Who Are You?",
            posterURL: nil, runtimeMinutes: 48
        )
    }

    private extension NowWatchingContent {
        static func sample(
            endTime: Bool, watched: Bool = false, startedMinutesAgo: Double = 7, paused: Bool = false
        ) -> Self {
            let start = Date.now.addingTimeInterval(-startedMinutesAgo * 60)
            return .init(
                startedAt: start, endsAt: start.addingTimeInterval(48 * 60), showsEndTime: endTime, watched: watched,
                pausedAt: paused ? .now : nil
            )
        }
    }

    #Preview("Lock Screen", as: .content, using: NowWatchingAttributes.preview) {
        NowWatchingLiveActivity()
    } contentStates: {
        NowWatchingContent.sample(endTime: true)
        NowWatchingContent.sample(endTime: false)
        NowWatchingContent.sample(endTime: true, startedMinutesAgo: 90)
        NowWatchingContent.sample(endTime: false, watched: true)
        NowWatchingContent.sample(endTime: false, startedMinutesAgo: 31, paused: true)
    }

    #Preview("Island compact", as: .dynamicIsland(.compact), using: NowWatchingAttributes.preview) {
        NowWatchingLiveActivity()
    } contentStates: {
        NowWatchingContent.sample(endTime: false)
    }

    #Preview("Island expanded", as: .dynamicIsland(.expanded), using: NowWatchingAttributes.preview) {
        NowWatchingLiveActivity()
    } contentStates: {
        NowWatchingContent.sample(endTime: true)
    }

    #Preview("Island compact, paused", as: .dynamicIsland(.compact), using: NowWatchingAttributes.preview) {
        NowWatchingLiveActivity()
    } contentStates: {
        NowWatchingContent.sample(endTime: false, paused: true)
    }

    #Preview("Island minimal", as: .dynamicIsland(.minimal), using: NowWatchingAttributes.preview) {
        NowWatchingLiveActivity()
    } contentStates: {
        NowWatchingContent.sample(endTime: false)
    }
#endif
