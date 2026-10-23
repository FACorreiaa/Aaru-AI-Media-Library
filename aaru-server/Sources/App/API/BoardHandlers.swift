import aaruAPI
import AaruCore
import Foundation

extension APIImplementation {
    func listBoard(_ input: Operations.ListBoard.Input) async throws -> Operations.ListBoard.Output {
        let viewer = try currentUser()
        let sort = input.query.sort.flatMap { BoardService.Sort(rawValue: $0.rawValue) } ?? .recent
        let page = try await services.board.feed(
            sort: sort, before: input.query.before.flatMap(UUID.init(uuidString:)), limit: input.query.limit,
            viewer: viewer
        )
        return try await .ok(.init(body: .json(.init(items: boardPosts(
            page.posts,
            veiled: page.veiled,
            viewer: viewer
        )))))
    }

    func listTitlePosts(_ input: Operations.ListTitlePosts.Input) async throws -> Operations.ListTitlePosts.Output {
        let viewer = try currentUser()
        guard let id = UUID(uuidString: input.path.id) else { throw AppError.notFound("That title isn't here.") }
        let page = try await services.board.posts(title: TitleID(id), limit: input.query.limit, viewer: viewer)
        return try await .ok(.init(body: .json(.init(items: boardPosts(
            page.posts,
            veiled: page.veiled,
            viewer: viewer
        )))))
    }

    func createBoardPost(_ input: Operations.CreateBoardPost.Input) async throws
        -> Operations.CreateBoardPost.Output
    {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let viewer = try currentUser()
        let post = try await services.board.create(
            body: body.body, title: body.title.map(MediaRef.init), rating: body.rating,
            spoiler: GroupService.SpoilerChoice(body.spoiler, free: body.spoilerFree), viewer: viewer
        )
        return try await .created(.init(body: .json(boardPost(post, veiled: false, viewer: viewer))))
    }

    func getBoardPost(_ input: Operations.GetBoardPost.Input) async throws -> Operations.GetBoardPost.Output {
        let viewer = try currentUser()
        let (post, veiled) = try await services.board.post(postID(input.path.postId), viewer: viewer)
        return try await .ok(.init(body: .json(boardPost(post, veiled: veiled, viewer: viewer))))
    }

    func editBoardPost(_ input: Operations.EditBoardPost.Input) async throws -> Operations.EditBoardPost.Output {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let viewer = try currentUser()
        let post = try await services.board.edit(postID(input.path.postId), body: body.body, viewer: viewer)
        return try await .ok(.init(body: .json(boardPost(post, veiled: false, viewer: viewer))))
    }

    func deleteBoardPost(_ input: Operations.DeleteBoardPost.Input) async throws
        -> Operations.DeleteBoardPost.Output
    {
        try await services.board.delete(postID(input.path.postId), viewer: currentUser())
        return .noContent(.init())
    }

    func upvoteBoardPost(_ input: Operations.UpvoteBoardPost.Input) async throws
        -> Operations.UpvoteBoardPost.Output
    {
        try await services.board.upvote(postID(input.path.postId), on: true, viewer: currentUser())
        return .noContent(.init())
    }

    func removeBoardPostUpvote(_ input: Operations.RemoveBoardPostUpvote.Input) async throws
        -> Operations.RemoveBoardPostUpvote.Output
    {
        try await services.board.upvote(postID(input.path.postId), on: false, viewer: currentUser())
        return .noContent(.init())
    }

    func listBoardPostUpvoters(_ input: Operations.ListBoardPostUpvoters.Input) async throws
        -> Operations.ListBoardPostUpvoters.Output
    {
        let users = try await services.board.upvoters(postID(input.path.postId), viewer: currentUser())
        return .ok(.init(body: .json(.init(items: users.map { .init($0) }))))
    }

    func listBoardComments(_ input: Operations.ListBoardComments.Input) async throws
        -> Operations.ListBoardComments.Output
    {
        let viewer = try currentUser()
        let page = try await services.board.comments(
            postID(input.path.postId), after: input.query.after.flatMap(UUID.init(uuidString:)),
            limit: input.query.limit, viewer: viewer
        )
        return .ok(.init(body: .json(.init(
            items: page.items.map { .init($0, viewer: viewer) },
            next: page.next?.uuidString
        ))))
    }

    func createBoardComment(_ input: Operations.CreateBoardComment.Input) async throws
        -> Operations.CreateBoardComment.Output
    {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let viewer = try currentUser()
        let replyTo = try body.replyTo.map { raw -> UUID in
            guard let id = UUID(uuidString: raw) else {
                throw GroupService.invalid("replyTo", "That comment isn't here.")
            }
            return id
        }
        let comment = try await services.board.comment(
            postID(input.path.postId), body: body.body, replyTo: replyTo, viewer: viewer
        )
        return .created(.init(body: .json(.init(comment, viewer: viewer))))
    }

    func deleteBoardComment(_ input: Operations.DeleteBoardComment.Input) async throws
        -> Operations.DeleteBoardComment.Output
    {
        guard let comment = UUID(uuidString: input.path.commentId) else {
            throw AppError.notFound("That comment isn't here.")
        }
        try await services.board.deleteComment(postID(input.path.postId), comment: comment, viewer: currentUser())
        return .noContent(.init())
    }

    /// A malformed id reads as a post that does not exist.
    private func postID(_ raw: String) throws -> UUID {
        guard let id = UUID(uuidString: raw) else { throw BoardService.noSuchPost }
        return id
    }

    private func boardPost(_ post: BoardPost, veiled: Bool, viewer: UserID) async throws
        -> Components.Schemas.BoardPost
    {
        try await boardPosts([post], veiled: veiled ? [post.id] : [], viewer: viewer)[0]
    }

    /// Hydrates the titles in one batch.
    private func boardPosts(
        _ posts: [BoardPost], veiled: Set<UUID>, viewer: UserID
    ) async throws -> [Components.Schemas.BoardPost] {
        let ids = Set(posts.compactMap(\.titleID))
        let titles = ids.isEmpty ? [] : try await stores.titles.titles(ids: Array(ids))
        let byID = Dictionary(titles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return posts.map { post in
            .init(post, title: post.titleID.flatMap { byID[$0] }, viewer: viewer, veiled: veiled.contains(post.id))
        }
    }
}

extension Components.Schemas.BoardPost {
    init(_ post: BoardPost, title: Title?, viewer: UserID, veiled: Bool) {
        self.init(
            id: post.id.uuidString, author: .init(post.author), title: title.map { .init($0) },
            rating: post.rating, body: post.body,
            // The stamp says where the author is in the title, so only the author sees it.
            spoiler: post.author.id == viewer ? post.spoiler.map(Components.Schemas.SpoilerStamp.init) : nil,
            createdAt: post.createdAt, editedAt: post.editedAt, upvotes: post.upvotes,
            upvotedByMe: post.upvotedByViewer, commentCount: post.commentCount, veiled: veiled,
            mine: post.author.id == viewer
        )
    }
}

extension Components.Schemas.BoardComment {
    init(_ comment: BoardComment, viewer: UserID) {
        self.init(
            id: comment.id.uuidString, postId: comment.postID.uuidString, author: comment.author.map { .init($0) },
            body: comment.deletedAt == nil ? comment.body : "", mentions: comment.mentions.map(\.description),
            mentionsAgent: comment.mentionsAgent, deleted: comment.deletedAt != nil, createdAt: comment.createdAt,
            fromAgent: comment.fromAgent, replyTo: comment.replyTo?.uuidString,
            mine: comment.author?.id == viewer
        )
    }
}
