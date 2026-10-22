#if os(iOS)
    import AaruCore
    import CryptoKit
    import Foundation
    import ImageIO
    import UniformTypeIdentifiers

    /// Artwork for the Live Activities (SCR-009): the extension cannot load from the network, so
    /// the app downsamples each poster, cover and thumbnail into the App Group as
    /// `now-playing-art/<sha256(url)>.jpg`, and the extension looks it up by the row's URL. A
    /// row whose art is not saved yet draws its kind's glyph. The newest dozen files are kept.
    enum NowPlayingArtwork {
        static let limit = 12
        static let maxPixel = 120

        private static var directory: URL? {
            FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)?
                .appending(path: "now-playing-art", directoryHint: .isDirectory)
        }

        static func fileURL(for url: String) -> URL? {
            let digest = SHA256.hash(data: Data(url.utf8)).map { String(format: "%02x", $0) }.joined()
            return directory?.appending(path: "\(digest).jpg")
        }

        /// The saved art for `url`, or nil until the app has saved it.
        static func load(for url: String?) -> Data? {
            guard let url, let fileURL = fileURL(for: url) else { return nil }
            return try? Data(contentsOf: fileURL)
        }

        /// Every row's art, for a state the app sees: on launch, while the activity runs, on
        /// Home's poll and in the background refresh.
        static func store(for state: NowPlayingActivityState) async {
            await store(state.items.compactMap(\.artworkURL))
        }

        /// Fetches what is missing, all at once; art already saved is only marked as used, so the
        /// trim keeps it. Best effort: a failed fetch leaves the glyph.
        static func store(_ urls: [String]) async {
            guard let directory, !urls.isEmpty else { return }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            await withTaskGroup(of: Void.self) { group in
                for url in Set(urls) {
                    guard let fileURL = fileURL(for: url), let source = URL(string: url) else { continue }
                    if FileManager.default.fileExists(atPath: fileURL.path()) {
                        try? FileManager.default.setAttributes(
                            [.modificationDate: Date.now],
                            ofItemAtPath: fileURL.path()
                        )
                        continue
                    }
                    group.addTask {
                        var request = URLRequest(url: source)
                        request.timeoutInterval = 6
                        guard let (data, _) = try? await URLSession.shared.data(for: request),
                              let small = downsample(data, maxPixel: maxPixel)
                        else { return }
                        try? small.write(to: fileURL, options: .atomic)
                    }
                }
            }
            trim(directory)
        }

        static func clear() {
            if let directory {
                try? FileManager.default.removeItem(at: directory)
            }
        }

        /// Keeps the `limit` most recently used files.
        private static func trim(_ directory: URL) {
            let key = URLResourceKey.contentModificationDateKey
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [key]
            ), files.count > limit else { return }
            let used = { (file: URL) in
                (try? file.resourceValues(forKeys: [key]).contentModificationDate) ?? .distantPast
            }
            for file in files.sorted(by: { used($0) > used($1) }).dropFirst(limit) {
                try? FileManager.default.removeItem(at: file)
            }
        }

        static func downsample(_ data: Data, maxPixel: Int) -> Data? {
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
