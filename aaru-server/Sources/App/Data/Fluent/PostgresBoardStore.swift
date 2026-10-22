import AaruCore
import FluentKit
import FluentSQL
import Foundation

struct PostgresBoardStore: BoardStore {
    let database: any Database

    private var sql: any SQLDatabase {
        get throws { try sqlDatabase(database) }
    }

    private struct PostRow: Decodable {
        let id: UUID
        let userId: UUID
        let handle: String
        let displayName: String?
        let titleId: UUID?
        let rating: Double?
        let body: String
        let spoilerSeason: Int?
        let spoilerEpisode: Int?
        let spoilerEnding: Bool
        let createdAt: Date
        let editedAt: Date?
        let upvotes: Int
        let upvotedByViewer: Bool
        let commentCount: Int

        var post: BoardPost {
            BoardPost(
                id: id,
                author: SocialUser(id: UserID(userId), handle: handle, displayName: displayName),
                titleID: titleId.map(TitleID.init),
                rating: rating,
                body: body,
                spoiler: spoilerEnding ? .ending : spoilerSeason.flatMap { season in
                    spoilerEpisode.map { .episode(EpisodePoint(season: season, episode: $0)) }
                },
                createdAt: createdAt,
                editedAt: editedAt,
                upvotes: upvotes,
                upvotedByViewer: upvotedByViewer,
                commentCount: commentCount
            )
        }
    }

    private struct CommentRow: Decodable {
        let id: UUID
        let postId: UUID
        let userId: UUID?
        let handle: String?
        let displayName: String?
        let authorKind: String
        let replyTo: UUID?
        let body: String
        let mentions: [UUID]
        let mentionsAgent: Bool
        let createdAt: Date
        let deletedAt: Date?

        var comment: BoardComment {
            let author = userId.flatMap { id in
                handle.map { SocialUser(id: UserID(id), handle: $0, displayName: displayName) }
            }
            return BoardComment(
                id: id, postID: postId, author: author, fromAgent: authorKind == "agent", replyTo: replyTo,
                body: body, mentions: mentions.map(UserID.init), mentionsAgent: mentionsAgent,
                createdAt: createdAt, deletedAt: deletedAt
            )
        }
    }

    private struct UserRow: Decodable {
        let userId: UUID
        let handle: String
        let displayName: String?
    }

    /// Shared SELECT + FROM for every post read. Deleted posts are filtered by each caller's WHERE.
    private static func postColumns(viewer: UserID) -> SQLQueryString {
        """
        SELECT b.id, b.user_id, p.handle, u.display_name, b.title_id, b.rating::float8 AS rating, b.body,
            b.spoiler_season, b.spoiler_episode, b.spoiler_ending, b.created_at, b.edited_at,
            (SELECT count(*)::int FROM board_upvotes v WHERE v.post_id = b.id) AS upvotes,
            EXISTS (SELECT 1 FROM board_upvotes v WHERE v.post_id = b.id AND v.user_id = \(bind: viewer.rawValue))
                AS upvoted_by_viewer,
            (SELECT count(*)::int FROM board_comments c WHERE c.post_id = b.id AND c.deleted_at IS NULL)
                AS comment_count
        FROM board_posts b
        JOIN profiles p ON p.user_id = b.user_id JOIN users u ON u.id = b.user_id
        """
    }

    private static let commentColumns: SQLQueryString = """
    SELECT c.id, c.post_id, c.user_id, p.handle, u.display_name, c.author_kind, c.reply_to, c.body,
        c.mentions, c.mentions_agent, c.created_at, c.deleted_at
    FROM board_comments c
    LEFT JOIN profiles p ON p.user_id = c.user_id LEFT JOIN users u ON u.id = c.user_id
    """

    func createPost(_ post: BoardPost) async throws -> BoardPost {
        let point: EpisodePoint? = if case let .episode(point) = post.spoiler {
            point
        } else {
            nil
        }
        try await sql.raw("""
        INSERT INTO board_posts (id, user_id, title_id, rating, body,
                                 spoiler_season, spoiler_episode, spoiler_ending, created_at)
        VALUES (\(bind: post.id), \(bind: post.author.id.rawValue), \(bind: post.titleID?.rawValue),
                \(bind: post.rating), \(bind: post.body), \(bind: point?.season), \(bind: point?.episode),
                \(bind: post.spoiler == .ending), \(bind: post.createdAt))
        """).run()
        return post
    }

    func post(_ id: UUID, viewer: UserID) async throws -> BoardPost? {
        try await sql.raw("""
        \(Self.postColumns(viewer: viewer)) WHERE b.id = \(bind: id) AND b.deleted_at IS NULL
        """).first(decoding: PostRow.self, keyDecodingStrategy: .convertFromSnakeCase)?.post
    }

    func feed(authors: [UserID], before: UUID?, limit: Int, viewer: UserID) async throws -> [BoardPost] {
        let ids = authors.map(\.rawValue)
        let paging: SQLQueryString = if let before {
            """
            AND (b.created_at, b.id) < (SELECT created_at, id FROM board_posts WHERE id = \(bind: before))
            """
        } else {
            ""
        }
        return try await sql.raw("""
        \(Self.postColumns(viewer: viewer))
        WHERE b.user_id = ANY(\(bind: ids)) AND b.deleted_at IS NULL \(paging)
        ORDER BY b.created_at DESC, b.id DESC LIMIT \(bind: limit)
        """).all(decoding: PostRow.self, keyDecodingStrategy: .convertFromSnakeCase).map(\.post)
    }

    func top(authors: [UserID], since: Date, limit: Int, viewer: UserID) async throws -> [BoardPost] {
        try await sql.raw("""
        \(Self.postColumns(viewer: viewer))
        WHERE b.user_id = ANY(\(bind: authors.map(\.rawValue))) AND b.deleted_at IS NULL
          AND b.created_at >= \(bind: since)
        ORDER BY upvotes DESC, b.created_at DESC, b.id DESC LIMIT \(bind: limit)
        """).all(decoding: PostRow.self, keyDecodingStrategy: .convertFromSnakeCase).map(\.post)
    }

    func posts(title: TitleID, authors: [UserID], limit: Int, viewer: UserID) async throws -> [BoardPost] {
        try await sql.raw("""
        \(Self.postColumns(viewer: viewer))
        WHERE b.title_id = \(bind: title.rawValue) AND b.user_id = ANY(\(bind: authors.map(\.rawValue)))
          AND b.deleted_at IS NULL
        ORDER BY b.created_at DESC, b.id DESC LIMIT \(bind: limit)
        """).all(decoding: PostRow.self, keyDecodingStrategy: .convertFromSnakeCase).map(\.post)
    }

    func editPost(_ id: UUID, body: String, now: Date) async throws {
        try await sql.raw("""
        UPDATE board_posts SET body = \(bind: body), edited_at = \(bind: now)
        WHERE id = \(bind: id) AND deleted_at IS NULL
        """).run()
    }

    func deletePost(_ id: UUID, now: Date) async throws {
        try await sql.raw("""
        UPDATE board_posts SET deleted_at = \(bind: now) WHERE id = \(bind: id) AND deleted_at IS NULL
        """).run()
    }

    func setUpvote(post: UUID, user: UserID, on: Bool) async throws { // swiftlint:disable:this identifier_name
        if on {
            try await sql.raw("""
            INSERT INTO board_upvotes (post_id, user_id) VALUES (\(bind: post), \(bind: user.rawValue))
            ON CONFLICT DO NOTHING
            """).run()
        } else {
            try await sql.raw("""
            DELETE FROM board_upvotes WHERE post_id = \(bind: post) AND user_id = \(bind: user.rawValue)
            """).run()
        }
    }

    func upvoters(post: UUID) async throws -> [SocialUser] {
        try await sql.raw("""
        SELECT v.user_id, p.handle, u.display_name
        FROM board_upvotes v JOIN profiles p ON p.user_id = v.user_id JOIN users u ON u.id = v.user_id
        WHERE v.post_id = \(bind: post) ORDER BY v.created_at, v.user_id
        """).all(decoding: UserRow.self, keyDecodingStrategy: .convertFromSnakeCase).map {
            SocialUser(id: UserID($0.userId), handle: $0.handle, displayName: $0.displayName)
        }
    }

    func addComment(_ comment: BoardComment) async throws -> BoardComment {
        try await sql.raw("""
        INSERT INTO board_comments (id, post_id, user_id, author_kind, reply_to, body, mentions,
                                    mentions_agent, created_at)
        VALUES (\(bind: comment.id), \(bind: comment.postID), \(bind: comment.author?.id.rawValue),
                \(bind: comment.fromAgent ? "agent" : "user"), \(bind: comment.replyTo), \(bind: comment.body),
                \(bind: comment.mentions.map(\.rawValue)), \(bind: comment.mentionsAgent),
                \(bind: comment.createdAt))
        """).run()
        return comment
    }

    func comment(_ id: UUID, post: UUID) async throws -> BoardComment? {
        try await sql.raw("""
        \(Self.commentColumns) WHERE c.id = \(bind: id) AND c.post_id = \(bind: post)
        """).first(decoding: CommentRow.self, keyDecodingStrategy: .convertFromSnakeCase)?.comment
    }

    func comments(post: UUID, after: UUID?, limit: Int) async throws -> [BoardComment] {
        let paging: SQLQueryString = if let after {
            """
            AND (c.created_at, c.id) > (SELECT created_at, id FROM board_comments WHERE id = \(bind: after))
            """
        } else {
            ""
        }
        return try await sql.raw("""
        \(Self.commentColumns) WHERE c.post_id = \(bind: post) \(paging)
        ORDER BY c.created_at, c.id LIMIT \(bind: limit)
        """).all(decoding: CommentRow.self, keyDecodingStrategy: .convertFromSnakeCase).map(\.comment)
    }

    func deleteComment(_ id: UUID, now: Date) async throws {
        try await sql.raw("""
        UPDATE board_comments SET deleted_at = \(bind: now) WHERE id = \(bind: id) AND deleted_at IS NULL
        """).run()
    }
}
