import AaruAPI
import AaruCore
import Foundation
import Observation

/// BOARD-003: the friends-only Board. Posts from friends, newest first or top this week.
@MainActor
@Observable
final class BoardModel {
    enum Sort: String, CaseIterable {
        case recent
        case top

        var label: String {
            switch self {
            case .recent: "Recent"
            case .top: "Top this week"
            }
        }
    }

    var sort: Sort = .recent
    private(set) var posts: [BoardPost] = []
    private(set) var hasLoaded = false
    /// Why the first load failed; the Board shows Try again instead of an empty page.
    private(set) var loadProblem: String?
    var problem: String?
    /// A full Recent page may have more behind it; Top never pages.
    private(set) var canShowOlder = false
    /// When page one last came back: a Board shown again after a while reloads it.
    @ObservationIgnored private(set) var loadedAt: Date?

    /// The composer's half-written post. It lives here, not in the composer, so switching to
    /// Lately, popping Friends or opening a post keeps it. Cleared once posted and on sign-out.
    var draftText = ""
    var draftTitle: BoardTitlePick?
    var draftRating: Double?
    var draftSpoiler = SpoilerChoice.auto
    /// A post on its way; the composer shows the spinner and takes no second send.
    private(set) var isPosting = false

    @ObservationIgnored let api: Client?

    init(api: Client?) {
        self.api = api
    }

    /// Loads the first page for the current sort and replaces what is shown.
    func load() async {
        guard let api else { return }
        let requested = sort
        do {
            switch try await api.listBoard(query: .init(sort: requested.payload)) {
            case let .ok(response):
                guard requested == sort else { return }
                let page = try response.body.json.items
                posts = page
                canShowOlder = BoardRules.hasOlder(sortIsRecent: requested == .recent, pageCount: page.count)
                hasLoaded = true
                loadProblem = nil
                loadedAt = .now
            case let .default(_, error):
                failLoad((try? error.body.json.message) ?? "The Board could not be loaded.")
            }
        } catch {
            failLoad("The Board could not be loaded. Aaru could not reach the server.")
        }
    }

    /// Whether page one is older than `maxAge` (a minute): the Board reloads it when shown again.
    func isStale(now: Date = .now, maxAge: TimeInterval = 60) -> Bool {
        guard let loadedAt else { return true }
        return now.timeIntervalSince(loadedAt) > maxAge
    }

    /// The next, older page of Recent.
    func showOlder() async {
        guard let api, sort == .recent, let before = posts.last?.id else { return }
        await run("Older posts could not be loaded.") {
            switch try await api.listBoard(query: .init(sort: .recent, before: before)) {
            case let .ok(response):
                // The sort changed while the page was coming: these are Recent posts, not Top's.
                guard sort == .recent else { return }
                let page = try response.body.json.items
                let known = Set(posts.map(\.id))
                posts.append(contentsOf: page.filter { !known.contains($0.id) })
                canShowOlder = BoardRules.hasOlder(sortIsRecent: true, pageCount: page.count)
            case let .default(_, error): throw Failure(try? error.body.json.message)
            }
        }
    }

    /// Marks a post as on its way. The composer calls it before it spawns the request, so a second
    /// tap or ⌘↩ finds it set. False when a post is already on its way.
    func beginPosting() -> Bool {
        guard !isPosting else { return false }
        isPosting = true
        return true
    }

    /// Posts the draft to the Board and shows the new post first. Called after `beginPosting()`.
    /// A rating needs a title. The spoiler choice only means something with a title. The draft
    /// clears once posted. True when posted.
    func postDraft() async -> Bool {
        defer { isPosting = false }
        guard let api else { return false }
        let title = draftTitle
        let request = Components.Schemas.BoardPostCreate(
            body: draftText.trimmingCharacters(in: .whitespacesAndNewlines),
            title: title?.mediaRef,
            rating: title == nil ? nil : draftRating,
            spoiler: title == nil ? nil : draftSpoiler.stamp,
            spoilerFree: title != nil && draftSpoiler == .free ? true : nil
        )
        let posted = await run("That post was not saved.") {
            switch try await api.createBoardPost(body: .json(request)) {
            case let .created(response):
                let created = try response.body.json
                posts.removeAll { $0.id == created.id }
                posts.insert(created, at: 0)
            case let .default(_, error): throw Failure(try? error.body.json.message)
            }
        }
        if posted {
            clearDraft()
        }
        return posted
    }

    /// Back to an empty composer.
    func clearDraft() {
        draftText = ""
        clearDraftTitle()
    }

    /// Takes the title off the draft, and the stars and spoiler choice with it.
    func clearDraftTitle() {
        draftTitle = nil
        draftRating = nil
        draftSpoiler = .auto
    }

    /// Upvotes or takes the upvote back, at once, and puts the post back if the server says no.
    func toggleUpvote(_ id: String) async {
        guard let api, let index = posts.firstIndex(where: { $0.id == id }) else { return }
        let before = posts[index]
        let next = BoardRules.toggleUpvote(upvotes: before.upvotes, upvotedByMe: before.upvotedByMe)
        posts[index].upvotes = next.upvotes
        posts[index].upvotedByMe = next.upvotedByMe
        let saved = await run("That upvote was not saved.") {
            if next.upvotedByMe {
                switch try await api.upvoteBoardPost(path: .init(postId: id)) {
                case .noContent: break
                case let .default(_, error): throw Failure(try? error.body.json.message)
                }
            } else {
                switch try await api.removeBoardPostUpvote(path: .init(postId: id)) {
                case .noContent: break
                case let .default(_, error): throw Failure(try? error.body.json.message)
                }
            }
        }
        if !saved, let index = posts.firstIndex(where: { $0.id == id }) {
            posts[index] = before
        }
    }

    /// A friend's title, added to the viewer's own library as Plan to …: the same journaled add as
    /// a tap anywhere else. True when it was added.
    func addToMyLibrary(_ title: TitleSummary) async -> Bool {
        guard let api else { return false }
        return await run("\(title.title) was not added.") {
            switch try await api.addLibraryItem(body: .json(.init(mediaRef: title.mediaRef, status: .wishlist))) {
            case .ok: break
            case let .default(_, error): throw Failure(try? error.body.json.message)
            }
        }
    }

    /// Shows posts loaded elsewhere (a title page's "From friends") so their upvotes work here.
    func adopt(_ items: [BoardPost]) {
        posts = items
        hasLoaded = true
    }

    /// Signing out forgets the Board.
    func reset() {
        sort = .recent
        posts = []
        hasLoaded = false
        loadProblem = nil
        problem = nil
        canShowOlder = false
        loadedAt = nil
        clearDraft()
    }

    /// The post screen reports an edit back.
    func replace(_ post: BoardPost) {
        if let index = posts.firstIndex(where: { $0.id == post.id }) {
            posts[index] = post
        }
    }

    /// The post screen reports a delete back.
    func remove(_ id: String) {
        posts.removeAll { $0.id == id }
    }

    private struct Failure: Error {
        let message: String?
        init(_ message: String?) {
            self.message = message
        }
    }

    /// A first load that fails is a Try again; a later one keeps what is shown.
    private func failLoad(_ message: String) {
        if hasLoaded {
            problem = message
        } else {
            loadProblem = message
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

private extension BoardModel.Sort {
    var payload: Operations.ListBoard.Input.Query.SortPayload {
        switch self {
        case .recent: .recent
        case .top: .top
        }
    }
}
