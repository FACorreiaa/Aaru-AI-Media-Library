import AaruAPI
import OpenAPIRuntime
import SwiftUI

/// Avatars (SOC-001b) come through the `/v1` client, so the session's token goes with them:
/// `AsyncImage` cannot send it. Decoded images are kept by URL; the URL carries the avatar's
/// version, so a new photo is a new key and nothing is ever stale. The app holds one, in the
/// environment.
@MainActor
@Observable
final class AvatarLoader {
    @ObservationIgnored private let api: Client?
    @ObservationIgnored private var images: [String: Image] = [:]
    @ObservationIgnored private var loading: [String: Task<Image?, Never>] = [:]

    /// A few hundred faces is plenty; past it the oldest are read again from `URLCache`.
    private static let limit = 300

    init(api: Client?) {
        self.api = api
    }

    func cached(_ path: String) -> Image? {
        images[path]
    }

    func image(for path: String) async -> Image? {
        if let image = images[path] {
            return image
        }
        if let task = loading[path] {
            return await task.value
        }
        let task = Task { await fetch(path) }
        loading[path] = task
        let image = await task.value
        loading[path] = nil
        if let image {
            if images.count >= Self.limit {
                images.removeAll()
            }
            images[path] = image
        }
        return image
    }

    private func fetch(_ path: String) async -> Image? {
        guard let api, let (userID, version) = Self.parse(path),
              case let .ok(response)? = try? await api.getUserAvatar(
                  path: .init(userId: userID), query: .init(v: version)
              ),
              case let .jpeg(body) = response.body,
              let data = try? await Data(collecting: body, upTo: 2 * 1024 * 1024)
        else { return nil }
        #if os(iOS)
            return UIImage(data: data).map(Image.init(uiImage:))
        #else
            return NSImage(data: data).map(Image.init(nsImage:))
        #endif
    }

    /// The user and version in an `avatarUrl` the API gave: `/v1/users/{id}/avatar?v=…`.
    nonisolated static func parse(_ path: String) -> (userID: String, version: Int64?)? {
        guard let match = path.wholeMatch(of: /\/v1\/users\/([0-9A-Fa-f-]{36})\/avatar(?:\?v=(\d+))?/) else {
            return nil
        }
        return (String(match.1), match.2.flatMap { Int64($0) })
    }
}

/// Someone's photo on a circle of `size`, or `fallback` (their monogram) while it loads, without
/// one, and wherever the app has no loader (the Mac's Settings scene).
struct AvatarView<Fallback: View>: View {
    let path: String?
    let size: CGFloat
    @ViewBuilder var fallback: () -> Fallback

    @Environment(AvatarLoader.self) private var loader: AvatarLoader?
    @State private var image: Image?

    var body: some View {
        ZStack {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                fallback()
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .task(id: path) {
            guard let path, let loader else {
                image = nil
                return
            }
            image = loader.cached(path)
            if image == nil {
                image = await loader.image(for: path)
            }
        }
    }
}
