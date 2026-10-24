import AaruAPI
import AaruCore
import Foundation
import Observation

/// BOARD-003: one Board post with its upvoters and comments.
@MainActor
@Observable
final class PostModel {
    private(set) var post: BoardPost?
    /// The post is gone or not visible to the viewer (a 404).
    private(set) var unavailable = false
    private(set) var upvoters: [SocialUser] = []
    private(set) var comments: [BoardComment] = []
    /// Where the next page of comments starts; nil when there is none.
    private(set) var next: String?
    var problem: String?

    @ObservationIgnored let api: Client?
    @ObservationIgnored let postId: String

    init(api: Client?, postId: String, initial: BoardPost?) {
        self.api = api
        self.postId = postId
        post = initial
    }

    /// Loads the post, its upvoters and its first page of comments together.
    func load() async {
        guard let api else { return }
        let postId = postId
        do {
            async let postCall = api.getBoardPost(path: .init(postId: postId))
            async let upvotersCall = api.listBoardPostUpvoters(path: .init(postId: postId))
            async let commentsCall = api.listBoardComments(path: .init(postId: postId), query: .init())
            switch try await postCall {
            case let .ok(response):
                post = try response.body.json
                unavailable = false
            case let .default(status, error):
                if status == 404 {
                    unavailable = true
                } else {
                    problem = (try? error.body.json.message) ?? "That post could not be loaded."
                }
            }
            if case let .ok(response) = try await upvotersCall {
                upvoters = try response.body.json.items
            }
            if case let .ok(response) = try await commentsCall {
                let page = try response.body.json
                comments = page.items
                next = page.next
            }
        } catch {
            problem = "That post could not be loaded. Aaru could not reach the server."
        }
    }

    func loadMoreComments() async {
        guard let api, BoardRules.shouldLoadMore(next: next), let after = next else { return }
        await run("More comments could not be loaded.") {
            switch try await api.listBoardComments(path: .init(postId: postId), query: .init(after: after)) {
            case let .ok(response):
                let page = try response.body.json
                comments = BoardRules.merge(comments, page.items)
                next = page.next
            case let .default(_, error): throw Failure(try? error.body.json.message)
            }
        }
    }

    /// "Show more comments": the next page, then on through pages the server emptied (hidden
    /// rows), five at most, so a tap shows more whenever there is more. As the web does.
    func showMoreComments() async {
        for _ in 0 ..< 5 {
            let before = comments.count
            await loadMoreComments()
            guard comments.count == before, problem == nil, BoardRules.shouldLoadMore(next: next) else { return }
        }
    }

    /// Adds a comment, or a reply under a top-level comment. True when posted.
    func comment(_ body: String, replyTo: String?) async -> Bool {
        guard let api else { return false }
        let request = Components.Schemas.BoardCommentCreate(
            body: body.trimmingCharacters(in: .whitespacesAndNewlines),
            replyTo: replyTo
        )
        return await run("That comment was not saved.") {
            switch try await api.createBoardComment(path: .init(postId: postId), body: .json(request)) {
            case let .created(response):
                let created = try response.body.json
                comments = BoardRules.merge(comments, [created])
                post?.commentCount += 1
            case let .default(_, error): throw Failure(try? error.body.json.message)
            }
        }
    }

    func deleteComment(_ id: String) async {
        guard let api else { return }
        await run("That comment was not deleted.") {
            switch try await api.deleteBoardComment(path: .init(postId: postId, commentId: id)) {
            case .noContent:
                comments = BoardRules.drop(comments, id: id)
                if let count = post?.commentCount {
                    post?.commentCount = max(0, count - 1)
                }
            case let .default(_, error): throw Failure(try? error.body.json.message)
            }
        }
    }

    /// Changes the post's text. True when saved.
    func edit(body: String) async -> Bool {
        guard let api else { return false }
        let request = Components.Schemas.BoardPostEdit(body: body.trimmingCharacters(in: .whitespacesAndNewlines))
        return await run("That edit was not saved.") {
            switch try await api.editBoardPost(path: .init(postId: postId), body: .json(request)) {
            case let .ok(response): post = try response.body.json
            case let .default(_, error): throw Failure(try? error.body.json.message)
            }
        }
    }

    /// Deletes the post. True when it is gone.
    func delete() async -> Bool {
        guard let api else { return false }
        return await run("That post was not deleted.") {
            switch try await api.deleteBoardPost(path: .init(postId: postId)) {
            case .noContent: break
            case let .default(_, error): throw Failure(try? error.body.json.message)
            }
        }
    }

    /// Upvotes or takes the upvote back, at once, and puts the post back if the server says no.
    func toggleUpvote() async {
        guard let api, let before = post else { return }
        let next = BoardRules.toggleUpvote(upvotes: before.upvotes, upvotedByMe: before.upvotedByMe)
        post?.upvotes = next.upvotes
        post?.upvotedByMe = next.upvotedByMe
        let saved = await run("That upvote was not saved.") {
            if next.upvotedByMe {
                switch try await api.upvoteBoardPost(path: .init(postId: postId)) {
                case .noContent: break
                case let .default(_, error): throw Failure(try? error.body.json.message)
                }
            } else {
                switch try await api.removeBoardPostUpvote(path: .init(postId: postId)) {
                case .noContent: break
                case let .default(_, error): throw Failure(try? error.body.json.message)
                }
            }
        }
        if saved {
            upvoters = await refreshedUpvoters() ?? upvoters
        } else {
            post = before
        }
    }

    /// Reports the post through the user report route; the note starts with `post:<id>` so the
    /// reviewer knows which post, as the web does. True when sent.
    func report(reason: Components.Schemas.ReportCreate.ReasonPayload, note: String?) async -> Bool {
        guard let api, let author = post?.author else { return false }
        let composed = ["post:\(postId)", note?.trimmingCharacters(in: .whitespacesAndNewlines)]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let request = Components.Schemas.ReportCreate(userId: author.userId, reason: reason, note: composed)
        return await run("That report was not sent.") {
            switch try await api.reportUser(body: .json(request)) {
            case .noContent: break
            case let .default(_, error): throw Failure(try? error.body.json.message)
            }
        }
    }

    private func refreshedUpvoters() async -> [SocialUser]? {
        guard let api else { return nil }
        if case let .ok(response)? = try? await api.listBoardPostUpvoters(path: .init(postId: postId)) {
            return try? response.body.json.items
        }
        return nil
    }

    private struct Failure: Error {
        let message: String?
        init(_ message: String?) {
            self.message = message
        }
    }

    /// Runs one request and turns any failure into one visible message. True when it succeeded.
    @discardableResult
    private func run(_ fallback: String, _ call: () async throws -> Void) async -> Bool {
        problem = nil
        do {
            try await call()
            return true
        } catch let failure as Failure {
            problem = failure.message ?? fallback
        } catch {
            problem = "\(fallback) Aaru could not reach the server."
        }
        return false
    }
}
