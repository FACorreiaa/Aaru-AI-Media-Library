import AaruCore
import Foundation

/// A link sent as a capture (AG-006). Aaru never fetches it: a catalog link names its title by id
/// in the URL itself, and a site with an export is pointed at its CSV importer.
enum CaptureLink: Equatable {
    /// TMDB, AniList or Open Library: the title the URL names.
    case title(ImportRow)
    /// Letterboxd or IMDb: their CSV export carries the whole list; Aaru does not read their pages.
    case useCSV(site: String)
    case unsupported

    static func parse(_ url: URL) -> CaptureLink {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              var host = url.host?.lowercased()
        else { return .unsupported }
        for prefix in ["www.", "m."] where host.hasPrefix(prefix) {
            host.removeFirst(prefix.count)
        }
        switch host {
        case "letterboxd.com", "boxd.it":
            return .useCSV(site: "Letterboxd")
        case "imdb.com":
            return .useCSV(site: "IMDb")
        default:
            return catalogTitle(host: host, url: url) ?? .unsupported
        }
    }

    /// /movie/603-the-matrix and /tv/1396 on TMDB, /anime/21/One-Piece on AniList (manga is not a
    /// kind Aaru keeps yet), /works/OL45804W/Fantastic_Mr_Fox on Open Library.
    private static func catalogTitle(host: String, url: URL) -> CaptureLink? {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { return nil }
        let id = parts[1]
        switch (host, parts[0]) {
        case ("themoviedb.org", "movie"):
            return leadingNumber(id).map { title(.movie, ExternalIDs(tmdb: $0), url: url) }
        case ("themoviedb.org", "tv"):
            return leadingNumber(id).map { title(.show, ExternalIDs(tmdb: $0), url: url) }
        case ("anilist.co", "anime"):
            return leadingNumber(id).map { title(.show, ExternalIDs(anilist: $0), url: url) }
        case ("openlibrary.org", "works") where id.hasPrefix("OL") && id.hasSuffix("W"):
            return title(.book, ExternalIDs(openLibrary: id), url: url)
        default:
            return nil
        }
    }

    private static func leadingNumber(_ segment: String) -> String? {
        let digits = segment.prefix { $0.isASCII && $0.isNumber }
        return digits.isEmpty ? nil : String(digits)
    }

    /// The row a link becomes. Matched by its id; the link stands in for a name until then.
    private static func title(_ type: MediaType, _ ids: ExternalIDs, url: URL) -> CaptureLink {
        let label = (url.host ?? "") + url.path
        return .title(ImportRow(
            sourceKey: url.absoluteString, type: type, title: label, ids: ids, status: .wishlist, lists: []
        ))
    }
}
