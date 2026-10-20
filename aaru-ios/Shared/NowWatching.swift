#if os(iOS)
    import ActivityKit
    import Foundation
    import ImageIO
    import UniformTypeIdentifiers

    /// The "Now watching" Live Activity (WID-005): one episode the user said they started, on the
    /// Lock Screen and in the Dynamic Island, with progress, "Ends at" / "left", and Mark watched.
    struct NowWatchingAttributes: ActivityAttributes {
        struct ContentState: Codable, Hashable {
            var startedAt: Date
            var endsAt: Date
            /// "Ends at 1:20 PM" instead of "41m left"; tapping the label flips it (Trakt's behaviour).
            var showsEndTime: Bool
            /// Set by Mark watched just before the activity ends, so its last frame says so.
            var watched: Bool
        }

        var libraryItemId: String
        var title: String
        var season: Int
        var episode: Int
        var episodeName: String?
        var posterURL: String?
        var runtimeMinutes: Int

        /// "S1 · E8 · Lanterns".
        var episodeLine: String {
            ["S\(season) · E\(episode)", episodeName].compactMap(\.self).joined(separator: " · ")
        }

        func matches(libraryItemId: String, season: Int, episode: Int) -> Bool {
            self.libraryItemId == libraryItemId && self.season == season && self.episode == episode
        }
    }

    /// Starting, flipping and ending the activity. Only one runs at a time.
    enum NowWatching {
        /// How long past the episode's end an activity may stay before it is ended.
        static let grace: TimeInterval = 30 * 60
        static let fallbackRuntime = 45

        static var current: Activity<NowWatchingAttributes>? {
            Activity<NowWatchingAttributes>.activities.first
        }

        /// Starts watching an episode, ending any other. The poster is fetched and downsampled
        /// into the App Group first: the Lock Screen view cannot load from the network.
        static func start(_ attributes: NowWatchingAttributes, now: Date = .now) async throws {
            await endAll(dismissal: .immediate)
            if let url = attributes.posterURL.flatMap(URL.init(string:)) {
                await NowWatchingArtwork.store(from: url)
            } else {
                NowWatchingArtwork.clear()
            }
            let endsAt = now.addingTimeInterval(TimeInterval(attributes.runtimeMinutes) * 60)
            let state = NowWatchingAttributes.ContentState(
                startedAt: now, endsAt: endsAt, showsEndTime: true, watched: false
            )
            _ = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: endsAt.addingTimeInterval(grace)),
                pushType: nil
            )
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
        /// background refresh.
        static func endStale(now: Date = .now) async {
            for activity in Activity<NowWatchingAttributes>.activities
                where activity.content.state.endsAt.addingTimeInterval(grace) <= now
            {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }

        static func endAll(dismissal: ActivityUIDismissalPolicy = .immediate) async {
            for activity in Activity<NowWatchingAttributes>.activities {
                await activity.end(nil, dismissalPolicy: dismissal)
            }
            NowWatchingArtwork.clear()
        }
    }

    /// The running activity's poster, downsampled into the App Group for the extension to draw.
    enum NowWatchingArtwork {
        static var fileURL: URL? {
            FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)?
                .appending(path: "now-watching-poster.jpg")
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
        }

        static func load() -> Data? {
            fileURL.flatMap { try? Data(contentsOf: $0) }
        }

        static func clear() {
            if let fileURL {
                try? FileManager.default.removeItem(at: fileURL)
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
