import Foundation

/// The fallback identity for a title: normalized name + year + type.
///
/// Only used after external ids fail to match. Two titles that share nothing but a
/// similar name must never be merged, which is why `year` and `type` are part of
/// the key and why an absent year makes the key weaker, not broader.
public struct MatchKey: Hashable, Sendable, CustomStringConvertible {
    public let normalizedTitle: String
    public let year: Int?
    public let type: MediaType

    public init(title: String, year: Int?, type: MediaType) {
        self.normalizedTitle = MatchKey.normalize(title)
        self.year = year
        self.type = type
    }

    public var description: String {
        "\(type.rawValue):\(normalizedTitle):\(year.map(String.init) ?? "-")"
    }

    /// Folds a display title down to something two providers can agree on.
    ///
    /// Lowercases, strips diacritics, drops a leading article, removes punctuation,
    /// and collapses whitespace. Deliberately conservative: it must not make two
    /// different works collide.
    public static func normalize(_ title: String) -> String {
        let folded = title.folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let unpunctuated = folded.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return " "
        }
        let collapsed = String(unpunctuated)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        return dropLeadingArticle(collapsed)
    }

    private static let leadingArticles = ["the ", "a ", "an "]

    private static func dropLeadingArticle(_ title: String) -> String {
        for article in leadingArticles where title.hasPrefix(article) {
            let stripped = String(title.dropFirst(article.count))
            // "The The" or a title that is only an article keeps its original form.
            return stripped.isEmpty ? title : stripped
        }
        return title
    }
}

public extension MatchKey {
    /// Whether two refs may describe the same work.
    ///
    /// External ids decide when either side has one in common. Name matching is the
    /// fallback and requires the same type; a missing year on one side is allowed,
    /// two different years are not.
    static func canMerge(_ lhs: MediaRef, _ rhs: MediaRef) -> Bool {
        // A movie and a show are never the same work — and TMDB/Trakt number them
        // separately, so a shared id across types is a coincidence, not a match.
        guard lhs.type == rhs.type else { return false }
        if lhs.ids.matches(rhs.ids) {
            return true
        }
        guard let left = lhs.matchKey,
              let right = rhs.matchKey,
              left.normalizedTitle == right.normalizedTitle,
              !left.normalizedTitle.isEmpty
        else { return false }
        switch (left.year, right.year) {
        case (nil, _), (_, nil): return true
        case let (a?, b?): return a == b
        }
    }

    /// IMP-020: whether a book one year off may still be the same work. Goodreads and Open
    /// Library often disagree on a first year by one, so a book may match one year off, but
    /// only when its author is also one of the hit's authors. Both years must be known. The
    /// caller still takes it only when exactly one hit qualifies. Books only: no other kind
    /// is loosened.
    static func canMergeBook(_ lhs: MediaRef, author: String?, _ rhs: MediaRef, byline: String?) -> Bool {
        guard lhs.type == .book, rhs.type == .book,
              let author, let byline, sameAuthor(author, byline: byline),
              let left = lhs.matchKey, let right = rhs.matchKey,
              !left.normalizedTitle.isEmpty, left.normalizedTitle == right.normalizedTitle,
              let a = left.year, let b = right.year
        else { return false }
        return abs(a - b) <= 1
    }

    /// Whether `author` is one of the names in `byline` (comma separated, as a catalog lists
    /// them). Case, accents, punctuation and spacing are ignored, so "James S.A. Corey" is
    /// "James S. A. Corey"; anything else must be the same letters.
    static func sameAuthor(_ author: String, byline: String) -> Bool {
        let wanted = authorKey(author)
        guard !wanted.isEmpty else { return false }
        return byline.split(separator: ",").contains { authorKey(String($0)) == wanted }
    }

    private static func authorKey(_ name: String) -> String {
        name.folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        .map(String.init).joined()
    }
}
