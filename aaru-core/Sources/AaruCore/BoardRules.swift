import Foundation

/// A Board comment as the thread rules see it. AaruCore cannot see the generated API types, so the
/// app conforms `Components.Schemas.BoardComment` to this (BOARD-003).
public protocol BoardThreadComment: Sendable {
    var id: String { get }
    var replyTo: String? { get }
    var deleted: Bool { get }
    var authorHandle: String? { get }
    /// The same comment as a blank "Comment deleted" row: deleted, empty body, no author, not mine.
    func tombstoned() -> Self
}

/// One top-level comment and the replies hung from it. Threads are one level deep.
public struct BoardThread<C: BoardThreadComment>: Sendable {
    public let comment: C
    public let replies: [C]

    public init(comment: C, replies: [C]) {
        self.comment = comment
        self.replies = replies
    }
}

/// How the friends-only Board reads in the Apple apps (BOARD-003). Pure display rules, the same
/// as `aaru-client/src/lib/board/model.ts`; every rule about who sees what is the server's.
public enum BoardRules {
    /// Posts per Recent page: the server's default page size.
    public static let pageSize = 20

    /// Whether "Show older" is offered: a full Recent page may have more behind it; Top never pages.
    public static func hasOlder(sortIsRecent: Bool, pageCount: Int) -> Bool {
        sortIsRecent && pageCount >= pageSize
    }

    /// A 1-10 rating as five symbols: whole stars, a half where odd.
    public static func stars(_ rating: Double) -> String {
        let value = clamped(rating)
        let full = value / 2
        let half = value % 2
        return String(repeating: "★", count: full)
            + String(repeating: "½", count: half)
            + String(repeating: "☆", count: 5 - full - half)
    }

    /// A 1-10 rating for a screen reader: `9` → "4½ of 5 stars".
    public static func ratingWords(_ rating: Double) -> String {
        let value = clamped(rating)
        let whole = value / 2
        let half = value % 2 == 1 ? "½" : ""
        let lead = whole > 0 || half.isEmpty ? String(whole) : ""
        return "\(lead)\(half) of 5 stars"
    }

    /// What posting a review does to the library, in words. Nil without a rating: it changes
    /// nothing. The status words are per kind and live in the app, so they come in as arguments.
    // swiftlint:disable:next function_parameter_count
    public static func reviewEffect(
        title: String,
        isShow: Bool,
        inLibrary: Bool,
        rating: Double?,
        finishedLabel: String,
        inProgressLabel: String
    ) -> String? {
        guard let rating else { return nil }
        let stars = stars(rating)
        if inLibrary {
            return "Updates your rating to \(stars). Its status stays."
        }
        if isShow {
            return "Adds \(title) to \(finishedLabel), or \(inProgressLabel) if it's still airing, \(stars)"
        }
        return "Adds \(title) to \(finishedLabel), \(stars)"
    }

    /// Replies under their top-level comment. A reply to a reply goes to its root; a missing parent
    /// makes a reply top-level; a cycle makes its members top-level rather than hang.
    public static func threads<C: BoardThreadComment>(_ items: [C]) -> [BoardThread<C>] {
        let byId = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // The id of the top-level comment `c` hangs from, or nil when `c` is top-level itself.
        func rootId(of c: C) -> String? {
            var seen: Set<String> = [c.id]
            var current = c
            while let parentId = current.replyTo {
                guard let parent = byId[parentId] else { break }
                if seen.contains(parent.id) {
                    return nil
                }
                seen.insert(parent.id)
                current = parent
            }
            return current.id == c.id ? nil : current.id
        }
        let roots = items.map { (comment: $0, root: rootId(of: $0)) }
        var order: [String] = []
        var comments: [String: C] = [:]
        var replies: [String: [C]] = [:]
        for entry in roots where entry.root == nil {
            order.append(entry.comment.id)
            comments[entry.comment.id] = entry.comment
        }
        for entry in roots {
            if let root = entry.root, comments[root] != nil {
                replies[root, default: []].append(entry.comment)
            }
        }
        return order.compactMap { id in
            comments[id].map { BoardThread(comment: $0, replies: replies[id] ?? []) }
        }
    }

    /// Comment pages joined by id, first-seen order kept.
    public static func merge<C: BoardThreadComment>(_ current: [C], _ page: [C]) -> [C] {
        var seen = Set(current.map(\.id))
        var out = current
        for c in page where seen.insert(c.id).inserted {
            out.append(c)
        }
        return out
    }

    /// A page can be empty and still have a next one (a cursor skipping hidden rows).
    public static func shouldLoadMore(next: String?) -> Bool {
        guard let next else { return false }
        return !next.isEmpty
    }

    public static func toggleUpvote(upvotes: Int, upvotedByMe: Bool) -> (upvotes: Int, upvotedByMe: Bool) {
        upvotedByMe
            ? (max(0, upvotes - 1), false)
            : (upvotes + 1, true)
    }

    public enum Empty: Equatable, Sendable { case noFriends, quiet }

    /// Why an empty Board is empty: no friends yet, or friends who have not posted. Nil with posts.
    public static func empty(postCount: Int, friendCount: Int) -> Empty? {
        if postCount > 0 {
            return nil
        }
        return friendCount == 0 ? .noFriends : .quiet
    }

    /// Who upvoted, in words: "Ana", "Ana and Ben", "Ana, Ben and 10 others". `names` are in the
    /// order given (the caller puts "You" first when the viewer upvoted). Nil with nobody.
    public static func upvotersLine(_ names: [String]) -> String? {
        switch names.count {
        case 0: return nil
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default:
            let rest = names.count - 2
            return "\(names[0]), \(names[1]) and \(rest) \(rest == 1 ? "other" : "others")"
        }
    }

    /// The loaded comments after one is deleted, as the server would page them: a top-level comment
    /// with live replies stays as a blank "Comment deleted" row so its replies keep their place;
    /// anything else leaves. A parent left with no live replies goes with it.
    public static func drop<C: BoardThreadComment>(_ items: [C], id: String) -> [C] {
        guard let target = items.first(where: { $0.id == id }) else { return items }
        func live(_ parent: String, without: String) -> Bool {
            items.contains { $0.replyTo == parent && $0.id != without && !$0.deleted }
        }
        return items.flatMap { c -> [C] in
            if c.id == id {
                return live(id, without: id) ? [c.tombstoned()] : []
            }
            // The reply was the last live one under a deleted parent: the parent goes too.
            if c.id == target.replyTo, c.deleted, !live(c.id, without: id) {
                return []
            }
            return [c]
        }
    }

    /// Reply on `comment`. A top-level comment is answered as itself. A reply is answered under its
    /// top-level comment (its `replyTo`, loaded or not), tagging the reply's author: `id` is sent as
    /// `replyTo`, `prefill` is `@ben ` for a reply and empty for a top-level comment.
    public static func replyTarget<C: BoardThreadComment>(_ comment: C) -> (id: String, prefill: String) {
        guard let parent = comment.replyTo else { return (comment.id, "") }
        return (parent, comment.authorHandle.map { "@\($0) " } ?? "")
    }

    /// The box's text when the reply target changes from one prefill to another: an untouched box (or
    /// one holding only the old prefill) takes the new one; typed words keep, with the new tag in
    /// front unless they already start with it.
    public static func prefillReply(_ text: String, from: String, to: String) -> String {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text == from {
            return to
        }
        let rest = !from.isEmpty && text.hasPrefix(from) ? String(text.dropFirst(from.count)) : text
        return rest.hasPrefix(to) ? rest : to + rest
    }

    /// How many characters are left, shown only near the limit: nil until 200 or fewer remain.
    public static func remaining(_ text: String, limit: Int = 4000) -> Int? {
        let left = limit - text.utf16.count
        return left <= 200 ? left : nil
    }

    /// A 1-10 rating rounded and held to that range.
    private static func clamped(_ rating: Double) -> Int {
        Int(max(0, min(10, rating.rounded(.toNearestOrAwayFromZero))))
    }
}
