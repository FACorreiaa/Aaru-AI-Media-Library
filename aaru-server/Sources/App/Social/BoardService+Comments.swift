import AaruCore
import Foundation

// BRD-001: comments under a Board post.

extension BoardService {
    static let defaultCommentPageSize = 50
    static let maxCommentPageSize = 100

    /// A page of comments and the cursor for the next one.
    struct CommentPage: Sendable {
        var items: [BoardComment]
        /// The id of the last row the store scanned, filtered or not; nil when that was the end.
        var next: UUID?
    }

    /// Oldest first, minus anyone blocked in either direction with the viewer. A deleted comment
    /// with live replies on this page stays as an empty-body `deletedAt` row; one without is
    /// dropped. The store pages over deleted and blocked rows too, so a page can come back shorter
    /// than `limit` (even empty): follow `next`, not the item count. A deleted parent whose replies
    /// sit on a later page is dropped.
    func comments(_ post: UUID, after: UUID?, limit: Int?, viewer: UserID) async throws -> CommentPage {
        _ = try await requireVisible(post, viewer: viewer)
        let size = min(max(limit ?? Self.defaultCommentPageSize, 1), Self.maxCommentPageSize)
        let hidden = try await blockedEitherWay(viewer)
        let scanned = try await stores.boards.comments(post: post, after: after, limit: size)
        let rows = scanned.filter { $0.author.map { !hidden.contains($0.id) } ?? true }
        let answered = Set(rows.filter { $0.deletedAt == nil }.compactMap(\.replyTo))
        let items: [BoardComment] = rows.compactMap { row in
            guard row.deletedAt != nil else { return row }
            guard answered.contains(row.id) else { return nil }
            var empty = row
            empty.body = ""
            return empty
        }
        return CommentPage(items: items, next: scanned.count < size ? nil : scanned.last?.id)
    }

    /// A comment this viewer can act on: live, on this post, and not by anyone blocked either way.
    private func liveComment(_ id: UUID, post: UUID, viewer: UserID) async throws -> BoardComment? {
        guard let found = try await stores.boards.comment(id, post: post), found.deletedAt == nil else { return nil }
        if let author = found.author, try await blockedEitherWay(viewer).contains(author.id) {
            return nil
        }
        return found
    }

    func comment(_ post: UUID, body: String, replyTo: UUID?, viewer: UserID) async throws -> BoardComment {
        let found = try await requireVisible(post, viewer: viewer)
        let author = try await social.requireHandle(viewer)
        let body = try Self.validBody(body)
        var parent: UUID?
        if let replyTo {
            guard let target = try await liveComment(replyTo, post: post, viewer: viewer) else {
                throw GroupService.invalid("replyTo", "That comment isn't here.")
            }
            // Nesting stays one level: a reply to a reply hangs off the top-level comment.
            parent = target.replyTo ?? target.id
        }
        let hidden = try await blockedEitherWay(viewer)
        var candidates = try await stores.social.friends(viewer).filter { !hidden.contains($0.id) }
        if found.author.id != viewer {
            candidates.append(found.author)
        }
        let (mentions, agent) = GroupService.mentions(in: body, users: candidates)
        return try await stores.boards.addComment(
            BoardComment(
                id: UUID(), postID: post, author: author, fromAgent: false, replyTo: parent, body: body,
                mentions: mentions.filter { $0 != viewer }, mentionsAgent: agent, createdAt: now()
            )
        )
    }

    /// The comment's author or the post's author.
    func deleteComment(_ post: UUID, comment id: UUID, viewer: UserID) async throws {
        let found = try await requireVisible(post, viewer: viewer)
        guard let target = try await liveComment(id, post: post, viewer: viewer) else {
            throw AppError.notFound("That comment isn't here.")
        }
        guard target.author?.id == viewer || found.author.id == viewer else {
            throw GroupService.forbidden("Only the comment's author or the post's author can delete it.")
        }
        try await stores.boards.deleteComment(id, now: now())
    }
}
