import AaruCore
import Foundation
import Testing
@testable import aaru

@Suite("Board store", .serialized)
struct BoardStoreTests {
    /// A user with a handle, which is what makes someone a Board author.
    private func author(_ stores: Stores) async throws -> SocialUser {
        let (id, _) = try await signedInUser(stores)
        let handle = "b" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()
        try await stores.social.saveProfile(id, handle: handle, displayName: .some(nil))
        return SocialUser(id: id, handle: handle, displayName: nil)
    }

    private func post(by author: SocialUser, at date: Date = Date(), body: String = "hello") -> BoardPost {
        BoardPost(id: UUID(), author: author, titleID: nil, rating: nil, body: body, spoiler: nil, createdAt: date)
    }

    @Test("BRD-001: feed is newest first and pages by before")
    func feedPages() async throws {
        try await withMigratedStores { stores in
            let alice = try await author(stores)
            let now = Date()
            let first = try await stores.boards.createPost(post(by: alice, at: now.addingTimeInterval(-30)))
            let second = try await stores.boards.createPost(post(by: alice, at: now.addingTimeInterval(-20)))
            let third = try await stores.boards.createPost(post(by: alice, at: now.addingTimeInterval(-10)))
            let page = try await stores.boards.feed(authors: [alice.id], before: nil, limit: 2, viewer: alice.id)
            #expect(page.map(\.id) == [third.id, second.id])
            let next = try await stores.boards.feed(authors: [alice.id], before: second.id, limit: 2, viewer: alice.id)
            #expect(next.map(\.id) == [first.id])
            #expect(next.first?.author == alice)
        }
    }

    @Test("BRD-001: upvotes are idempotent and counted")
    func upvotes() async throws {
        try await withMigratedStores { stores in
            let alice = try await author(stores)
            let bob = try await author(stores)
            let created = try await stores.boards.createPost(post(by: alice))
            try await stores.boards.setUpvote(post: created.id, user: alice.id, on: true)
            try await stores.boards.setUpvote(post: created.id, user: alice.id, on: true)
            try await stores.boards.setUpvote(post: created.id, user: bob.id, on: true)
            let counted = try #require(try await stores.boards.post(created.id, viewer: alice.id))
            #expect(counted.upvotes == 2)
            #expect(counted.upvotedByViewer)
            #expect(try await stores.boards.upvoters(post: created.id).count == 2)
            try await stores.boards.setUpvote(post: created.id, user: alice.id, on: false)
            try await stores.boards.setUpvote(post: created.id, user: alice.id, on: false)
            let after = try #require(try await stores.boards.post(created.id, viewer: alice.id))
            #expect(after.upvotes == 1)
            #expect(!after.upvotedByViewer)
        }
    }

    @Test("BRD-001: top orders by upvotes inside the window")
    func topWindow() async throws {
        try await withMigratedStores { stores in
            let alice = try await author(stores)
            let bob = try await author(stores)
            let now = Date()
            let quiet = try await stores.boards.createPost(post(by: alice, at: now.addingTimeInterval(-10)))
            let loved = try await stores.boards.createPost(post(by: alice, at: now.addingTimeInterval(-20)))
            try await stores.boards.setUpvote(post: loved.id, user: alice.id, on: true)
            try await stores.boards.setUpvote(post: loved.id, user: bob.id, on: true)
            let ranked = try await stores.boards.top(
                authors: [alice.id], since: now.addingTimeInterval(-60), limit: 10, viewer: alice.id
            )
            #expect(ranked.map(\.id) == [loved.id, quiet.id])
            let narrow = try await stores.boards.top(
                authors: [alice.id], since: now.addingTimeInterval(-15), limit: 10, viewer: alice.id
            )
            #expect(narrow.map(\.id) == [quiet.id])
        }
    }

    @Test("BRD-001: deleted posts vanish")
    func deletedPosts() async throws {
        try await withMigratedStores { stores in
            let alice = try await author(stores)
            let created = try await stores.boards.createPost(post(by: alice))
            try await stores.boards.deletePost(created.id, now: Date())
            #expect(try await stores.boards.post(created.id, viewer: alice.id) == nil)
            let feed = try await stores.boards.feed(authors: [alice.id], before: nil, limit: 10, viewer: alice.id)
            #expect(feed.isEmpty)
        }
    }

    @Test("BRD-001: title posts carry rating and spoiler, comments keep deleted rows")
    func titlePostAndComments() async throws {
        try await withMigratedStores { stores in
            let alice = try await author(stores)
            let title = Title(type: .movie, title: "Dune \(uniqueID())")
            try await stores.titles.insert(title)
            let created = try await stores.boards.createPost(BoardPost(
                id: UUID(), author: alice, titleID: title.id, rating: 8.5, body: "great",
                spoiler: .episode(EpisodePoint(season: 1, episode: 2)), createdAt: Date()
            ))
            let about = try await stores.boards.posts(title: title.id, authors: [alice.id], limit: 5, viewer: alice.id)
            #expect(about.map(\.id) == [created.id])
            #expect(about.first?.rating == 8.5)
            #expect(about.first?.spoiler == .episode(EpisodePoint(season: 1, episode: 2)))

            let now = Date()
            let kept = try await stores.boards.addComment(BoardComment(
                id: UUID(), postID: created.id, author: alice, fromAgent: false, replyTo: nil, body: "one",
                mentions: [alice.id], mentionsAgent: false, createdAt: now
            ))
            let gone = try await stores.boards.addComment(BoardComment(
                id: UUID(), postID: created.id, author: nil, fromAgent: true, replyTo: kept.id, body: "two",
                mentions: [], mentionsAgent: false, createdAt: now.addingTimeInterval(1)
            ))
            try await stores.boards.deleteComment(gone.id, now: now)
            let all = try await stores.boards.comments(post: created.id, after: nil, limit: 10)
            #expect(all.map(\.id) == [kept.id, gone.id])
            #expect(all[0].mentions == [alice.id])
            #expect(all[1].fromAgent && all[1].author == nil && all[1].deletedAt != nil)
            let after = try await stores.boards.comments(post: created.id, after: kept.id, limit: 10)
            #expect(after.map(\.id) == [gone.id])
            #expect(try await stores.boards.comment(kept.id, post: created.id)?.body == "one")
            let counted = try #require(try await stores.boards.post(created.id, viewer: alice.id))
            #expect(counted.commentCount == 1)
        }
    }

    @Test("BRD-001: account deletion leaves no board rows")
    func accountDeletion() async throws {
        try await withMigratedStores { stores in
            let alice = try await author(stores)
            let created = try await stores.boards.createPost(post(by: alice))
            try await stores.boards.setUpvote(post: created.id, user: alice.id, on: true)
            _ = try await stores.boards.addComment(BoardComment(
                id: UUID(), postID: created.id, author: alice, fromAgent: false, replyTo: nil, body: "c",
                mentions: [], mentionsAgent: false, createdAt: Date()
            ))
            try await stores.users.deleteUser(alice.id)
            #expect(try await rowsReferencing(alice.id) == [:])
        }
    }

    @Test("BRD-001: deleting an account keeps other people's replies to its comments")
    func replySurvivesParentAccountDeletion() async throws {
        try await withMigratedStores { stores in
            let ana = try await author(stores)
            let ben = try await author(stores)
            let created = try await stores.boards.createPost(post(by: ben))
            let top = try await stores.boards.addComment(BoardComment(
                id: UUID(), postID: created.id, author: ana, fromAgent: false, replyTo: nil, body: "top",
                mentions: [], mentionsAgent: false, createdAt: Date()
            ))
            let reply = try await stores.boards.addComment(BoardComment(
                id: UUID(), postID: created.id, author: ben, fromAgent: false, replyTo: top.id, body: "reply",
                mentions: [], mentionsAgent: false, createdAt: Date().addingTimeInterval(1)
            ))
            try await stores.users.deleteUser(ana.id)
            let survivor = try #require(try await stores.boards.comment(reply.id, post: created.id))
            #expect(survivor.body == "reply")
            #expect(survivor.replyTo == nil)
        }
    }
}
