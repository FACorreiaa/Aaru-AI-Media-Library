import Foundation
import Testing
@testable import AaruCore

struct BoardRulesTests {
    struct Comment: BoardThreadComment, Equatable {
        var id: String
        var replyTo: String?
        var deleted = false
        var authorHandle: String?
        var body = ""

        func tombstoned() -> Comment {
            Comment(id: id, replyTo: replyTo, deleted: true, authorHandle: nil, body: "")
        }
    }

    private func comment(
        _ id: String,
        _ replyTo: String? = nil,
        deleted: Bool = false,
        by handle: String? = nil
    ) -> Comment {
        Comment(id: id, replyTo: replyTo, deleted: deleted, authorHandle: handle, body: id)
    }

    private func ids(_ items: [Comment]) -> [String] {
        items.map(\.id)
    }

    @Test func starsAreFiveSymbolsWithAHalf() {
        #expect(BoardRules.stars(9) == "★★★★½")
        #expect(BoardRules.stars(10) == "★★★★★")
        #expect(BoardRules.stars(1) == "½☆☆☆☆")
        #expect(BoardRules.stars(4) == "★★☆☆☆")
    }

    @Test func ratingInWords() {
        #expect(BoardRules.ratingWords(9) == "4½ of 5 stars")
        #expect(BoardRules.ratingWords(2) == "1 of 5 stars")
        #expect(BoardRules.ratingWords(1) == "½ of 5 stars")
        #expect(BoardRules.ratingWords(4) == "2 of 5 stars")
    }

    @Test func olderPostsOnlyAfterAFullRecentPage() {
        #expect(BoardRules.pageSize == 20)
        #expect(BoardRules.hasOlder(sortIsRecent: true, pageCount: 20))
        #expect(!BoardRules.hasOlder(sortIsRecent: true, pageCount: 19))
        #expect(!BoardRules.hasOlder(sortIsRecent: false, pageCount: 20))
    }

    @Test func reviewEffectSaysWhatItDoesToTheLibrary() {
        #expect(BoardRules.reviewEffect(
            title: "Arrival",
            isShow: false,
            inLibrary: false,
            rating: 8,
            finishedLabel: "Watched",
            inProgressLabel: "Watching"
        )
            == "Adds Arrival to Watched, ★★★★☆")
        #expect(BoardRules.reviewEffect(
            title: "Dune",
            isShow: false,
            inLibrary: false,
            rating: 8,
            finishedLabel: "Read",
            inProgressLabel: "Reading"
        )
            == "Adds Dune to Read, ★★★★☆")
        #expect(BoardRules.reviewEffect(
            title: "Severance",
            isShow: true,
            inLibrary: false,
            rating: 9,
            finishedLabel: "Watched",
            inProgressLabel: "Watching"
        )
            == "Adds Severance to Watched, or Watching if it's still airing, ★★★★½")
        #expect(BoardRules.reviewEffect(
            title: "Arrival",
            isShow: false,
            inLibrary: true,
            rating: 9,
            finishedLabel: "Watched",
            inProgressLabel: "Watching"
        )
            == "Updates your rating to ★★★★½. Its status stays.")
        #expect(BoardRules.reviewEffect(
            title: "Arrival",
            isShow: false,
            inLibrary: false,
            rating: nil,
            finishedLabel: "Watched",
            inProgressLabel: "Watching"
        ) == nil)
    }

    @Test func threadsRepliesUnderTheirParent() {
        let items = [comment("C1"), comment("R1", "C1"), comment("C2"), comment("R2", "C1")]
        let threads = BoardRules.threads(items)
        #expect(threads.map(\.comment.id) == ["C1", "C2"])
        #expect(threads.map { ids($0.replies) } == [["R1", "R2"], []])
        let orphan = BoardRules.threads([comment("O", "gone")])
        #expect(orphan.map(\.comment.id) == ["O"])
        #expect(orphan[0].replies.isEmpty)
    }

    @Test func aReplyToAReplyLandsUnderItsRoot() {
        let threads = BoardRules.threads([comment("C1"), comment("R1", "C1"), comment("R1a", "R1")])
        #expect(threads.map(\.comment.id) == ["C1"])
        #expect(ids(threads[0].replies) == ["R1", "R1a"])
    }

    @Test func repliesStayUnderADeletedParent() {
        let threads = BoardRules.threads([comment("C1", deleted: true), comment("R1", "C1"), comment("R2", "C1")])
        #expect(threads.map(\.comment.id) == ["C1"])
        #expect(ids(threads[0].replies) == ["R1", "R2"])
    }

    @Test func aCycleMakesTopLevelThreadsAndDoesNotHang() {
        let threads = BoardRules.threads([comment("A", "B"), comment("B", "A")])
        #expect(threads.map(\.comment.id) == ["A", "B"])
        #expect(threads.allSatisfy { $0.replies.isEmpty })
    }

    @Test func mergeDedupesByIdKeepingFirstSeenOrder() {
        let a = comment("a"), b = comment("b"), c = comment("c")
        #expect(ids(BoardRules.merge([a, b], [b, c])) == ["a", "b", "c"])
    }

    @Test func loadsMoreWheneverNextIsSet() {
        #expect(BoardRules.shouldLoadMore(next: "x"))
        #expect(!BoardRules.shouldLoadMore(next: nil))
    }

    @Test func togglesAnUpvote() {
        let toggled = BoardRules.toggleUpvote(upvotes: 3, upvotedByMe: false)
        #expect(toggled == (4, true))
        #expect(BoardRules.toggleUpvote(upvotes: toggled.upvotes, upvotedByMe: toggled.upvotedByMe) == (3, false))
    }

    @Test func upvotesClampAtZero() {
        #expect(BoardRules.toggleUpvote(upvotes: 0, upvotedByMe: true) == (0, false))
    }

    @Test func tellsAnEmptyBoardFromAQuietOne() {
        #expect(BoardRules.empty(postCount: 0, friendCount: 0) == .noFriends)
        #expect(BoardRules.empty(postCount: 0, friendCount: 2) == .quiet)
        #expect(BoardRules.empty(postCount: 1, friendCount: 2) == nil)
    }

    @Test func namesTheFirstTwoUpvotersThenCountsTheRest() {
        #expect(BoardRules.upvotersLine([]) == nil)
        #expect(BoardRules.upvotersLine(["Ana"]) == "Ana")
        #expect(BoardRules.upvotersLine(["Ana", "Ben"]) == "Ana and Ben")
        #expect(BoardRules.upvotersLine(["Ana", "Ben", "Cy"]) == "Ana, Ben and 1 other")
        #expect(BoardRules.upvotersLine(["Ana", "Ben"] + Array(repeating: "x", count: 10)) == "Ana, Ben and 10 others")
    }

    @Test func aDeletedCommentWithLiveRepliesBecomesABlankRow() {
        let items = [comment("a", by: "ana"), comment("b", "a")]
        let left = BoardRules.drop(items, id: "a")
        #expect(ids(left) == ["a", "b"])
        #expect(left[0].deleted)
        #expect(left[0].body.isEmpty)
        #expect(left[0].authorHandle == nil)
        #expect(ids(BoardRules.threads(left)[0].replies) == ["b"])
    }

    @Test func aDeletedCommentWithoutRepliesLeavesAndSoDoesAnEmptiedDeletedParent() {
        #expect(BoardRules.drop([comment("a")], id: "a").isEmpty)
        #expect(BoardRules.drop([comment("a", deleted: true), comment("b", "a")], id: "b").isEmpty)
        let kept = [comment("a"), comment("b", "a"), comment("c", "a")]
        #expect(ids(BoardRules.drop(kept, id: "b")) == ["a", "c"])
        #expect(ids(BoardRules.drop(kept, id: "zzz")) == ["a", "b", "c"])
    }

    @Test func repliesGoUnderTheTopLevelCommentTaggingTheAuthor() {
        let top = BoardRules.replyTarget(comment("a", by: "ana"))
        #expect(top.id == "a")
        #expect(top.prefill.isEmpty)
        let reply = BoardRules.replyTarget(comment("b", "a", by: "ben"))
        #expect(reply.id == "a")
        #expect(reply.prefill == "@ben ")
    }

    @Test func anOrphanReplyIsAnsweredUnderItsOwnReplyTo() {
        let orphan = comment("b", "gone", by: "ben")
        #expect(BoardRules.threads([orphan])[0].comment.id == "b")
        #expect(BoardRules.replyTarget(orphan).id == "gone")
    }

    @Test func swapsAPrefillWithoutLosingTypedWords() {
        #expect(BoardRules.prefillReply("", from: "", to: "@ben ") == "@ben ")
        #expect(BoardRules.prefillReply("hi", from: "", to: "@ben ") == "@ben hi")
        #expect(BoardRules.prefillReply("@ben ", from: "@ben ", to: "@cy ") == "@cy ")
        #expect(BoardRules.prefillReply("@ben great", from: "@ben ", to: "@cy ") == "@cy great")
        #expect(BoardRules.prefillReply("@ben hi", from: "@ben ", to: "@ana ") == "@ana hi")
        #expect(BoardRules.prefillReply("@ben ", from: "@ben ", to: "") == "")
        #expect(BoardRules.prefillReply("@ben hi", from: "@ben ", to: "") == "hi")
    }

    @Test func remainingShowsOnlyNearTheLimit() {
        #expect(BoardRules.remaining(String(repeating: "a", count: 3700)) == nil)
        #expect(BoardRules.remaining(String(repeating: "a", count: 3799)) == nil)
        #expect(BoardRules.remaining(String(repeating: "a", count: 3800)) == 200)
        #expect(BoardRules.remaining(String(repeating: "a", count: 3850)) == 150)
        #expect(BoardRules.remaining(String(repeating: "a", count: 4010)) == -10)
        #expect(BoardRules.remaining("hi", limit: 1000) == nil)
    }
}
