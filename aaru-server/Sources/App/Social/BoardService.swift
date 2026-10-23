import AaruCore
import Foundation

/// BRD-001: the friends-only Board. A post is visible to its author and to the author's
/// friends, unless either side blocked the other.
/// A class, not a struct: it holds a whole `Stores` and a `LibraryService`, and inline in `Services`
/// it pushed the router's setup past the test threads' stack in debug builds.
final class BoardService: Sendable {
    let stores: Stores
    let resolver: TitleResolver
    let library: LibraryService
    let now: @Sendable () -> Date

    init(
        stores: Stores,
        resolver: TitleResolver,
        library: LibraryService,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.stores = stores
        self.resolver = resolver
        self.library = library
        self.now = now
    }

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

    /// A page of posts and the ones this viewer should see behind a spoiler veil.
    struct Page: Sendable {
        var posts: [BoardPost]
        var veiled: Set<UUID>
    }

    var social: SocialService {
        SocialService(stores: stores)
    }

    /// Posts by the viewer's audience. `top` is the last seven days by upvotes and ignores `before`.
    func feed(sort: Sort, before: UUID?, limit: Int?, viewer: UserID) async throws -> Page {
        let authors = try await audience(viewer)
        let posts: [BoardPost]
        switch sort {
        case .recent:
            let size = min(max(limit ?? Self.defaultPageSize, 1), Self.maxPageSize)
            posts = try await stores.boards.feed(authors: authors, before: before, limit: size, viewer: viewer)
        case .top:
            posts = try await stores.boards.top(
                authors: authors, since: now().addingTimeInterval(-Self.topWindow), limit: Self.topLimit,
                viewer: viewer
            )
        }
        return try await Page(posts: posts, veiled: veiled(posts, viewer: viewer))
    }

    /// Posts about one title by the viewer's audience, newest first.
    func posts(title: TitleID, limit: Int?, viewer: UserID) async throws -> Page {
        let authors = try await audience(viewer)
        let size = min(max(limit ?? Self.defaultPageSize, 1), Self.maxPageSize)
        let posts = try await stores.boards.posts(title: title, authors: authors, limit: size, viewer: viewer)
        return try await Page(posts: posts, veiled: veiled(posts, viewer: viewer))
    }

    /// Posts whose spoiler stamp is ahead of the viewer's own progress. Progress is read once per title.
    func veiled(_ posts: [BoardPost], viewer: UserID) async throws -> Set<UUID> {
        let stamped = posts.filter { $0.spoiler != nil && $0.titleID != nil && $0.author.id != viewer }
        var progress: [TitleID: TitleProgress] = [:]
        for title in Set(stamped.compactMap(\.titleID)) {
            progress[title] = try await stores.groupKinds.progress(title: title, users: [viewer])[viewer]
        }
        return Set(stamped.filter { GroupService.veils($0.spoiler, $0.titleID.flatMap { progress[$0] }) }.map(\.id))
    }

    func create(
        body: String, title ref: MediaRef?, rating: Double?, spoiler: GroupService.SpoilerChoice, viewer: UserID
    ) async throws -> BoardPost {
        // The store's reads join profiles: a post by someone without a handle would vanish.
        let author = try await social.requireHandle(viewer)
        let body = try Self.validBody(body)
        // Validate before any catalog call.
        var stored: Double?
        if let rating {
            guard ref != nil else { throw GroupService.invalid("rating", "Pick the title you are rating.") }
            stored = try Rating(rating).value
        }
        var title: Title?
        if let ref {
            title = try await resolver.resolve(ref)
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
        // A rating is a library write: a new title lands as Watched, an existing one keeps its status.
        if let ref, let title, let stored {
            let existing = try await stores.library.item(userID: viewer, titleID: title.id)
            let itemID = if let existing {
                existing.id
            } else {
                try await library.add(ref, status: .finished, userID: viewer).item.id
            }
            _ = try await library.patch(itemID, userID: viewer, patch: ItemPatch(rating: stored))
        }
        return try await stores.boards.createPost(
            BoardPost(
                id: UUID(), author: author, titleID: title?.id, rating: stored, body: body, spoiler: stamp,
                createdAt: now()
            )
        )
    }

    func post(_ id: UUID, viewer: UserID) async throws -> (post: BoardPost, veiled: Bool) {
        let found = try await requireVisible(id, viewer: viewer)
        return try await (found, !veiled([found], viewer: viewer).isEmpty)
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

    func upvote(_ id: UUID, on: Bool, viewer: UserID) async throws { // swiftlint:disable:this identifier_name
        _ = try await requireVisible(id, viewer: viewer)
        try await stores.boards.setUpvote(post: id, user: viewer, on: on)
    }

    /// Who upvoted, minus anyone blocked in either direction with the viewer.
    func upvoters(_ id: UUID, viewer: UserID) async throws -> [SocialUser] {
        _ = try await requireVisible(id, viewer: viewer)
        let hidden = try await blockedEitherWay(viewer)
        return try await stores.boards.upvoters(post: id).filter { !hidden.contains($0.id) }
    }

    /// The viewer and their friends, minus anyone blocked in either direction.
    func audience(_ viewer: UserID) async throws -> [UserID] {
        let friends = try await stores.social.friends(viewer).map(\.id)
        let hidden = try await blockedEitherWay(viewer)
        return [viewer] + friends.filter { !hidden.contains($0) }
    }

    /// Everyone the viewer blocked plus everyone who blocked the viewer.
    func blockedEitherWay(_ viewer: UserID) async throws -> Set<UserID> {
        let blocked = try await stores.social.blocked(by: viewer).map(\.id)
        let blockers = try await stores.social.blockers(of: viewer)
        return Set(blocked).union(blockers)
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
