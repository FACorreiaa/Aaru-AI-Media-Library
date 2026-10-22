#if os(iOS)
    import AaruCore
    import SwiftUI
    import WidgetKit

    // MARK: Previews for "Now playing": 1, 2 and 3 rows, paused and watched (SCR-009).

    private extension NowPlayingActivityItem {
        static func episode(minutesIn: Double = 7, paused: Bool = false, watched: Bool = false) -> Self {
            let start = Date.now.addingTimeInterval(-minutesIn * 60)
            return .init(
                id: "andor", kind: .episode, title: "Andor", subtitle: "S2 · E8 · Who Are You?", service: "Stremio",
                startedAt: start, endsAt: start.addingTimeInterval(48 * 60), pausedAt: paused ? .now : nil,
                watched: watched, libraryItemId: "preview", season: 2, episode: 8
            )
        }

        static func track() -> Self {
            let start = Date.now.addingTimeInterval(-70)
            return .init(
                id: "track", kind: .track, title: "Everything In Its Right Place", subtitle: "Radiohead",
                service: "YouTube Music", startedAt: start, endsAt: start.addingTimeInterval(251)
            )
        }

        static func video(paused: Bool = false) -> Self {
            let start = Date.now.addingTimeInterval(-4 * 60)
            return .init(
                id: "video", kind: .video, title: "How the Field of Reeds was mapped", subtitle: "Egyptology Today",
                service: "YouTube", startedAt: start, endsAt: start.addingTimeInterval(19 * 60),
                pausedAt: paused ? .now : nil
            )
        }
    }

    private extension NowPlayingActivityState {
        static let one = Self(items: [.episode()])
        static let oneEndTime = Self(items: [.episode()], showsEndTime: true)
        static let onePaused = Self(items: [.episode(minutesIn: 31, paused: true)])
        static let oneWatched = Self(items: [.episode(minutesIn: 47, watched: true)])
        static let two = Self(items: [.episode(), .track()])
        static let three = Self(items: [.episode(), .video(), .track()])
        static let threePaused = Self(items: [.episode(minutesIn: 31, paused: true), .video(paused: true), .track()])
        static let twoWatched = Self(items: [.episode(minutesIn: 47, watched: true), .track()])
    }

    #Preview("Lock Screen", as: .content, using: NowPlayingActivityAttributes()) {
        NowPlayingLiveActivity()
    } contentStates: {
        NowPlayingActivityState.one
        NowPlayingActivityState.oneEndTime
        NowPlayingActivityState.onePaused
        NowPlayingActivityState.oneWatched
        NowPlayingActivityState.two
        NowPlayingActivityState.three
        NowPlayingActivityState.threePaused
        NowPlayingActivityState.twoWatched
    }

    #Preview("Island compact", as: .dynamicIsland(.compact), using: NowPlayingActivityAttributes()) {
        NowPlayingLiveActivity()
    } contentStates: {
        NowPlayingActivityState.one
        NowPlayingActivityState.onePaused
        NowPlayingActivityState.three
    }

    #Preview("Island expanded", as: .dynamicIsland(.expanded), using: NowPlayingActivityAttributes()) {
        NowPlayingLiveActivity()
    } contentStates: {
        NowPlayingActivityState.oneEndTime
        NowPlayingActivityState.two
        NowPlayingActivityState.three
    }

    #Preview("Island minimal", as: .dynamicIsland(.minimal), using: NowPlayingActivityAttributes()) {
        NowPlayingLiveActivity()
    } contentStates: {
        NowPlayingActivityState.one
        NowPlayingActivityState.two
    }

    #Preview(
        "Now watching, by hand",
        as: .content,
        using: NowWatchingAttributes(
            libraryItemId: "preview", title: "Andor", season: 2, episode: 8, episodeName: "Who Are You?",
            runtimeMinutes: 48
        )
    ) {
        NowWatchingLiveActivity()
    } contentStates: {
        NowWatchingContent(
            startedAt: .now.addingTimeInterval(-7 * 60), endsAt: .now.addingTimeInterval(41 * 60),
            showsEndTime: true, watched: false
        )
    }
#endif
