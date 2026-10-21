#if os(iOS)
    import AaruCore
    import ActivityKit
    import Foundation
    import ImageIO
    import UniformTypeIdentifiers

    /// The "Now watching" Live Activity (WID-005, SCR-008): one episode on the Lock Screen and in
    /// the Dynamic Island, with progress, "Ends at" / "left", and Mark watched. The user starts it
    /// by hand, the app starts it when it sees a scrobble, or the server starts it by push. The
    /// types live in AaruCore so the server encodes the same keys; ActivityKit matches a
    /// push-to-start on the type's name, so it stays `NowWatchingAttributes`.
    extension NowWatchingAttributes: @retroactive ActivityAttributes {
        public typealias ContentState = NowWatchingContent
    }

    /// Starting, flipping and ending the activity. Only one runs at a time.
    enum NowWatching {
        /// How long past the episode's end (or the pause) an activity may stay before it is ended.
        static let grace: TimeInterval = 30 * 60
        static let fallbackRuntime = 45

        static var current: Activity<NowWatchingAttributes>? {
            Activity<NowWatchingAttributes>.activities.first
        }

        /// The activity following one scrobble session, if one runs.
        static func activity(watchEventId: UUID) -> Activity<NowWatchingAttributes>? {
            Activity<NowWatchingAttributes>.activities.first { $0.attributes.watchEventId == watchEventId }
        }

        /// Starts watching an episode, ending any other. The poster is fetched and downsampled
        /// into the App Group first: the Lock Screen view cannot load from the network.
        static func start(_ attributes: NowWatchingAttributes, now: Date = .now) async throws {
            await endAll(dismissal: .immediate)
            await storeArtwork(for: attributes)
            let endsAt = now.addingTimeInterval(TimeInterval(attributes.runtimeMinutes) * 60)
            let state = NowWatchingContent(startedAt: now, endsAt: endsAt, showsEndTime: true, watched: false)
            _ = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: aliveUntil(state)),
                pushType: nil
            )
        }

        /// Starts the activity for a scrobble the app saw before the server's push did (SCR-008).
        /// It asks for a push token, which the registrar hands to the server so pause, resume and
        /// stop reach it.
        static func startFromScrobble(_ attributes: NowWatchingAttributes, content: NowWatchingContent) async throws {
            await endAll(dismissal: .immediate)
            await storeArtwork(for: attributes)
            _ = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: content, staleDate: aliveUntil(content)),
                pushType: .token
            )
        }

        /// The poster for the Lock Screen, or none. An activity the server started by push has none
        /// until the app sees it.
        static func storeArtwork(for attributes: NowWatchingAttributes) async {
            if let url = attributes.posterURL.flatMap(URL.init(string:)) {
                await NowWatchingArtwork.store(from: url)
            } else {
                NowWatchingArtwork.clear()
            }
        }

        static func toggleEndTime() async {
            guard let activity = current else { return }
            var state = activity.content.state
            state.showsEndTime.toggle()
            await activity.update(ActivityContent(state: state, staleDate: activity.content.staleDate))
        }

        /// Called after an episode is ticked anywhere: the matching activity shows "Watched" for a
        /// moment, then goes.
        static func episodeWatched(libraryItemId: String, season: Int, episode: Int) async {
            for activity in Activity<NowWatchingAttributes>.activities
                where activity.attributes.matches(libraryItemId: libraryItemId, season: season, episode: episode)
            {
                var state = activity.content.state
                state.watched = true
                await activity.end(
                    ActivityContent(state: state, staleDate: nil),
                    dismissalPolicy: .after(.now.addingTimeInterval(8))
                )
            }
        }

        /// A whole season ticked: any activity for an episode of it ends.
        static func seasonWatched(libraryItemId: String, season: Int) async {
            for activity in Activity<NowWatchingAttributes>.activities
                where activity.attributes.libraryItemId == libraryItemId && activity.attributes.season == season
            {
                await episodeWatched(libraryItemId: libraryItemId, season: season, episode: activity.attributes.episode)
            }
        }

        /// Activities never outlive runtime + grace: run when the app comes forward and in the
        /// background refresh. A paused one stays until the pause is that old.
        static func endStale(now: Date = .now) async {
            for activity in Activity<NowWatchingAttributes>.activities
                where aliveUntil(activity.content.state) <= now
            {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }

        /// When an activity in this state is stale: the episode's end, or the pause if later, plus
        /// the grace.
        static func aliveUntil(_ state: NowWatchingContent) -> Date {
            max(state.endsAt, state.pausedAt ?? state.endsAt).addingTimeInterval(grace)
        }

        static func endAll(dismissal: ActivityUIDismissalPolicy = .immediate) async {
            for activity in Activity<NowWatchingAttributes>.activities {
                await activity.end(nil, dismissalPolicy: dismissal)
            }
            NowWatchingArtwork.clear()
        }
    }

    /// The running activity's poster, downsampled into the App Group for the extension to draw.
    /// The poster's URL is kept beside it, so an activity the server started never draws the
    /// poster of the one before.
    enum NowWatchingArtwork {
        static var fileURL: URL? {
            FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)?
                .appending(path: "now-watching-poster.jpg")
        }

        private static var sourceURL: URL? {
            fileURL?.deletingLastPathComponent().appending(path: "now-watching-poster.url")
        }

        static func store(from url: URL) async {
            guard let fileURL else { return }
            var request = URLRequest(url: url)
            request.timeoutInterval = 6
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let small = downsample(data, maxPixel: 160)
            else {
                clear()
                return
            }
            try? small.write(to: fileURL, options: .atomic)
            if let sourceURL {
                try? Data(url.absoluteString.utf8).write(to: sourceURL, options: .atomic)
            }
        }

        /// The stored poster, if it is the one at `posterURL`.
        static func load(for posterURL: String?) -> Data? {
            guard let posterURL, let fileURL, let sourceURL,
                  let source = try? Data(contentsOf: sourceURL),
                  URL(string: posterURL)?.absoluteString == String(bytes: source, encoding: .utf8)
            else { return nil }
            return try? Data(contentsOf: fileURL)
        }

        static func clear() {
            for url in [fileURL, sourceURL].compactMap(\.self) {
                try? FileManager.default.removeItem(at: url)
            }
        }

        private static func downsample(_ data: Data, maxPixel: Int) -> Data? {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                  ] as CFDictionary)
            else { return nil }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                output, UTType.jpeg.identifier as CFString, 1, nil
            ) else { return nil }
            CGImageDestinationAddImage(
                destination,
                image,
                [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary
            )
            return CGImageDestinationFinalize(destination) ? output as Data : nil
        }
    }
#endif
