import AaruCore
import Foundation

// BRD-001 Board half of the data layer boundary.

/// One post on the Board. `rating` needs a title. Counts and `upvotedByViewer` are read-time values.
struct BoardPost: Sendable, Equatable {
    let id: UUID
    let author: SocialUser
    let titleID: TitleID?
    let rating: Double?
    var body: String
    let spoiler: SpoilerStamp?
    let createdAt: Date
    var editedAt: Date?
    var upvotes: Int = 0
    var upvotedByViewer = false
    var commentCount = 0
}

/// One comment under a post. `author` is nil for Aaru (`fromAgent`) and once the account is gone.
struct BoardComment: Sendable, Equatable {
    let id: UUID
    let postID: UUID
    let author: SocialUser?
    let fromAgent: Bool
    let replyTo: UUID?
    var body: String
    let mentions: [UserID]
    let mentionsAgent: Bool
    let createdAt: Date
    var deletedAt: Date?
}

protocol BoardStore: Sendable {
    func createPost(_ post: BoardPost) async throws -> BoardPost
    /// Nil when the post is unknown or deleted.
    func post(_ id: UUID, viewer: UserID) async throws -> BoardPost?
    /// Posts by these authors, newest first, keyset-paged by the id of the last post seen.
    func feed(authors: [UserID], before: UUID?, limit: Int, viewer: UserID) async throws -> [BoardPost]
    /// Posts by these authors created since `since`: upvotes descending, then newest.
    func top(authors: [UserID], since: Date, limit: Int, viewer: UserID) async throws -> [BoardPost]
    /// Posts about one title by these authors, newest first.
    func posts(title: TitleID, authors: [UserID], limit: Int, viewer: UserID) async throws -> [BoardPost]
    func editPost(_ id: UUID, body: String, now: Date) async throws
    /// Soft delete: the post vanishes from every read.
    func deletePost(_ id: UUID, now: Date) async throws
    /// Idempotent both ways.
    func setUpvote(post: UUID, user: UserID, on: Bool) async throws // swiftlint:disable:this identifier_name
    func upvoters(post: UUID) async throws -> [SocialUser]
    func addComment(_ comment: BoardComment) async throws -> BoardComment
    func comment(_ id: UUID, post: UUID) async throws -> BoardComment?
    /// Oldest first. Includes deleted comments (`deletedAt` set); the service filters them.
    func comments(post: UUID, after: UUID?, limit: Int) async throws -> [BoardComment]
    /// Soft delete.
    func deleteComment(_ id: UUID, now: Date) async throws
}
