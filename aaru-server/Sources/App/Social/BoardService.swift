import AaruCore
import Foundation

/// BRD-001: the friends-only Board. A post is visible to its author and to the author's
/// friends, unless either side blocked the other.
struct BoardService: Sendable {
    let stores: Stores
    let resolver: TitleResolver
    let library: LibraryService
    var now: @Sendable () -> Date = { Date() }

    static let maxBodyLength = 4000
    static let defaultPageSize = 20
    static let maxPageSize = 50
    static let topLimit = 10
    static let topWindow: TimeInterval = 7 * 24 * 3600
    /// Missing, deleted, someone else's: all read the same.
    static let noSuchPost = AppError.notFound("That post isn't here.")

    enum Sort: String, Sendable {
        case recent
        case top
    }

    private var social: SocialService {
        SocialService(stores: stores)
    }

    /// Posts by the viewer's audience. `top` is the last seven days by upvotes and ignores `before`.
    func feed(sort: Sort, before: UUID?, limit: Int?, viewer: UserID) async throws -> [BoardPost] {
        let authors = try await audience(viewer)
        switch sort {
        case .recent:
            let size = min(max(limit ?? Self.defaultPageSize, 1), Self.maxPageSize)
            return try await stores.boards.feed(authors: authors, before: before, limit: size, viewer: viewer)
        case .top:
            return try await stores.boards.top(
                authors: authors, since: now().addingTimeInterval(-Self.topWindow), limit: Self.topLimit,
                viewer: viewer
            )
        }
    }

    func create(
        body: String, title ref: MediaRef?, rating: Double?, spoiler: GroupService.SpoilerChoice, viewer: UserID
    ) async throws -> BoardPost {
        // The store's reads join profiles: a post by someone without a handle would vanish.
        let author = try await social.requireHandle(viewer)
        let body = try Self.validBody(body)
        var title: Title?
        if let ref {
            title = try await resolver.resolve(ref)
        }
        var stored: Double?
        if let rating {
            guard title != nil else { throw GroupService.invalid("rating", "Pick the title you are rating.") }
            stored = try Rating(rating).value
        }
        var stamp: SpoilerStamp?
        if let title {
            switch spoiler {
            case .free: stamp = nil
            case let .stamp(given): stamp = given
            case .auto:
                let mine = try await stores.groupKinds.progress(title: title.id, users: [viewer])[viewer]
                stamp = mine.flatMap(GroupService.autoStamp)
            }
        }
        return try await stores.boards.createPost(
            BoardPost(
                id: UUID(), author: author, titleID: title?.id, rating: stored, body: body, spoiler: stamp,
                createdAt: now()
            )
        )
    }

    func post(_ id: UUID, viewer: UserID) async throws -> BoardPost {
        try await requireVisible(id, viewer: viewer)
    }

    func edit(_ id: UUID, body: String, viewer: UserID) async throws -> BoardPost {
        let original = try await requireVisible(id, viewer: viewer)
        guard original.author.id == viewer else { throw Self.onlyAuthor }
        try await stores.boards.editPost(id, body: Self.validBody(body), now: now())
        return try await requireVisible(id, viewer: viewer)
    }

    func delete(_ id: UUID, viewer: UserID) async throws {
        let original = try await requireVisible(id, viewer: viewer)
        guard original.author.id == viewer else { throw Self.onlyAuthor }
        try await stores.boards.deletePost(id, now: now())
    }

    /// The viewer and their friends, minus anyone blocked in either direction.
    func audience(_ viewer: UserID) async throws -> [UserID] {
        let friends = try await stores.social.friends(viewer).map(\.id)
        let blocked = try await Set(stores.social.blocked(by: viewer).map(\.id))
        let blockers = try await stores.social.blockers(of: viewer)
        return [viewer] + friends.filter { !blocked.contains($0) && !blockers.contains($0) }
    }

    func requireVisible(_ id: UUID, viewer: UserID) async throws -> BoardPost {
        guard let post = try await stores.boards.post(id, viewer: viewer) else { throw Self.noSuchPost }
        guard post.author.id == viewer else {
            guard try await stores.social.areFriends(viewer, post.author.id),
                  try await !stores.social.isBlocked(viewer, post.author.id)
            else { throw Self.noSuchPost }
            return post
        }
        return post
    }

    private static let onlyAuthor = GroupService.forbidden("Only the author can change this post.")

    static func validBody(_ raw: String) throws -> String {
        let body = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw GroupService.invalid("body", "Write something first.") }
        guard body.count <= maxBodyLength else {
            throw GroupService.invalid("body", "Keep posts under \(maxBodyLength) characters.")
        }
        return body
    }
}
