import AaruAPI
import AaruCore
import Foundation

typealias BoardPost = Components.Schemas.BoardPost
typealias BoardComment = Components.Schemas.BoardComment

extension BoardComment: @retroactive BoardThreadComment {
    public var authorHandle: String? {
        author?.handle
    }

    /// The same comment as a blank "Comment deleted" row.
    public func tombstoned() -> Self {
        var copy = self
        copy.deleted = true
        copy.body = ""
        copy.author = nil
        copy.mine = false
        return copy
    }
}

/// The post screen, pushed from a post's comment count. It carries the row's post, when there is
/// one, so the screen draws at once while the rest loads. Its destination is registered once, in
/// `FriendsContent`.
struct PostRoute: Hashable {
    let postId: String
    var initial: BoardPost?
}

/// A title the Board composer starts with: enough to show it, send it and word what posting does.
/// It comes from a search hit or from a title page.
struct BoardTitlePick: Hashable {
    let mediaRef: Components.Schemas.MediaRef
    let title: String
    let year: Int?
    let posterUrl: String?
    let type: Components.Schemas.MediaType
    let isAnime: Bool
    let inLibrary: Bool

    init(_ hit: CatalogHit) {
        mediaRef = hit.mediaRef
        title = hit.title
        year = hit.year
        posterUrl = hit.posterUrl
        type = hit._type
        isAnime = hit.isAnime
        inLibrary = hit.libraryItemId != nil
    }

    init(_ summary: Components.Schemas.TitleSummary, inLibrary: Bool) {
        mediaRef = summary.mediaRef
        title = summary.title
        year = summary.year
        posterUrl = summary.posterUrl
        type = summary._type
        isAnime = summary.isAnime
        self.inLibrary = inLibrary
    }
}

/// Posts about one title from the viewer's friends (title page). Empty on any failure: the page
/// just has nothing to show.
func titlePosts(api: Client?, titleId: String) async -> [BoardPost] {
    guard let api else { return [] }
    do {
        if case let .ok(response) = try await api.listTitlePosts(path: .init(id: titleId)) {
            return try response.body.json.items
        }
    } catch {
        return []
    }
    return []
}
