import AaruCore
import Foundation

/// IMP-013 and IMP-014: anime lists from MyAnimeList (XML export) and AniList (public list by
/// username), and their manga lists too (MNG-002). Both carry hard ids (`mal`, `anilist`), so rows
/// resolve through AniList and the same show imported from both lands on one title. Episodes are
/// season 1, as for every AniList entry.
enum AnimeListImport {
    /// MAL and AniList statuses on Aaru's five (IMP-013). On hold (AniList: paused) is Aaru's on
    /// hold (LIB-007); rewatching is still in progress. MAL's manga list says reading and plan to
    /// read; its numeric codes are the anime list's.
    static func status(_ value: String) -> LibraryStatus? {
        switch value.lowercased().replacingOccurrences(of: " ", with: "") {
        case "watching", "reading", "1", "current", "repeating", "rereading": .inProgress
        case "on-hold", "onhold", "3", "paused": .onHold
        case "completed", "2": .finished
        case "dropped", "4": .dropped
        case "plantowatch", "plantoread", "6", "planning": .wishlist
        default: nil
        }
    }

    /// A manga's chapter or volume as read: a completed entry exported with 0 read means all of
    /// them, when the total is known. Zero is none.
    static func read(_ count: Int, total: Int?, status: LibraryStatus?) -> Int? {
        let read = status == .finished && count == 0 ? total ?? 0 : count
        return read > 0 ? read : nil
    }

    /// Episodes 1…n of season 1, the AniList shape.
    static func watched(_ count: Int) -> [EpisodeKey]? {
        guard count > 0 else { return nil }
        return (1 ... count).compactMap { try? EpisodeKey(season: 1, episode: $0) }
    }

    /// A score on Aaru's 1–10 scale; 0 (MAL and AniList's "no score") is none.
    static func rating(_ score: Double?) -> Double? {
        score.flatMap { (1 ... 10).contains($0) ? $0 : nil }
    }

    /// A completed entry exported with 0 progress means every episode.
    static func progress(_ watched: Int, total: Int?, status: LibraryStatus?, isMovie: Bool) -> [EpisodeKey]? {
        guard !isMovie else { return nil }
        return Self.watched(status == .finished && watched == 0 ? total ?? 0 : watched)
    }
}

// MARK: MyAnimeList XML (IMP-013)

/// MAL's export is flat XML: one `<anime>` element per entry with simple child elements, some in
/// CDATA. Read with a small scanner rather than `XMLParser`, which needs libxml2 on Linux.
enum MALListParser {
    static func parse(_ text: String) throws -> [ImportRow] {
        guard text.contains("<myanimelist"),
              text.contains("<anime>") || text.contains("<manga>") || text.contains("</myinfo>")
        else {
            throw ImportFormatError(
                message: "This does not look like a MyAnimeList export. Export your anime or manga list from "
                    + "MAL and upload the .xml (or .xml.gz) file."
            )
        }
        return animeRows(text) + mangaRows(text)
    }

    /// MAL's manga export (MNG-002): `<manga>` entries with their own MAL ids, read chapters and
    /// volumes.
    static func mangaRows(_ text: String) -> [ImportRow] {
        blocks("manga", in: text).compactMap { block in
            guard let id = field("manga_mangadb_id", in: block), Int(id) != nil,
                  let title = field("manga_title", in: block)
            else { return nil }
            let status = field("my_status", in: block).flatMap(AnimeListImport.status)
            func count(_ name: String) -> Int? {
                field(name, in: block).flatMap { Int($0) }
            }
            return ImportRow(
                sourceKey: "mal-manga:\(id)",
                type: .manga,
                title: title,
                ids: ExternalIDs(mal: id),
                status: status,
                rating: AnimeListImport.rating(field("my_score", in: block).flatMap(Double.init)),
                finishedAt: field("my_finish_date", in: block).flatMap(Date.catalogDay),
                lists: [],
                mangaChapter: AnimeListImport.read(
                    count("my_read_chapters") ?? 0, total: count("manga_chapters"), status: status
                ),
                mangaVolume: AnimeListImport.read(
                    count("my_read_volumes") ?? 0, total: count("manga_volumes"), status: status
                ),
                knowsOnHold: true
            )
        }
    }

    static func animeRows(_ text: String) -> [ImportRow] {
        blocks("anime", in: text).compactMap { block in
            guard let id = field("series_animedb_id", in: block), Int(id) != nil,
                  let title = field("series_title", in: block)
            else { return nil }
            let isMovie = field("series_type", in: block)?.lowercased() == "movie"
            let status = field("my_status", in: block).flatMap(AnimeListImport.status)
            return ImportRow(
                sourceKey: "mal:\(id)",
                type: isMovie ? .movie : .show,
                title: title,
                ids: ExternalIDs(mal: id),
                status: status,
                rating: AnimeListImport.rating(field("my_score", in: block).flatMap(Double.init)),
                finishedAt: field("my_finish_date", in: block).flatMap(Date.catalogDay),
                lists: [],
                watched: AnimeListImport.progress(
                    field("my_watched_episodes", in: block).flatMap { Int($0) } ?? 0,
                    total: field("series_episodes", in: block).flatMap { Int($0) },
                    status: status, isMovie: isMovie
                ),
                knowsOnHold: true
            )
        }
    }

    /// The contents of every `<name>…</name>` element, in order.
    static func blocks(_ name: String, in text: String) -> [Substring] {
        var found: [Substring] = []
        var rest = text[...]
        while let open = rest.range(of: "<\(name)>"), let close = rest.range(
            of: "</\(name)>",
            range: open.upperBound ..< rest.endIndex
        ) {
            found.append(rest[open.upperBound ..< close.lowerBound])
            rest = rest[close.upperBound...]
        }
        return found
    }

    /// One child element's text: CDATA unwrapped, entities decoded, blank and MAL's empty
    /// `0000-00-00` dates treated as absent.
    static func field(_ name: String, in block: Substring) -> String? {
        guard let value = blocks(name, in: String(block)).first else { return nil }
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("<![CDATA["), text.hasSuffix("]]>") {
            text = String(text.dropFirst(9).dropLast(3))
        } else {
            text = decodeEntities(text)
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || text == "0000-00-00" ? nil : text
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = text
        for (entity, char) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&#039;", "'")] {
            out = out.replacingOccurrences(of: entity, with: char)
        }
        return out.replacingOccurrences(of: "&amp;", with: "&")
    }
}

// MARK: AniList (IMP-014)

protocol AniListListReading: Sendable {
    /// The user's anime and manga lists as import rows. A private list or unknown user is
    /// `.notFound`.
    func listRows(userName: String) async throws -> [ImportRow]
}
