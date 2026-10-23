import AaruCore
import Foundation

/// One row of an import, as the parser read it. This is what is kept; the uploaded file is not.
struct ImportRow: Codable, Sendable, Equatable {
    /// The row's identity in its source, for the person reading the plan (a Letterboxd URI, an
    /// IMDb const, a Goodreads book id).
    var sourceKey: String?
    var type: MediaType
    var title: String
    var year: Int?
    /// Authors, for books: narrows a title search when there is no ISBN.
    var author: String?
    var ids: ExternalIDs
    /// What the source says about the user's relationship. `nil` means "say nothing".
    var status: LibraryStatus?
    /// On Aaru's 1–10 scale.
    var rating: Double?
    var finishedAt: Date?
    /// Goodreads custom shelves: each becomes one Aaru list.
    var lists: [String]
    /// Set when the parser already knows the row cannot be imported (an IMDb episode row).
    var unsupported: String?
    /// Watched episodes, for shows (Trakt history). Ticked on create; missing ones filled on update.
    var watched: [EpisodeKey]?
    /// Manga (MNG-002): the last chapter and volume read. Moved forward on update, never back.
    var mangaChapter: Int?
    var mangaVolume: Int?
    /// On a source list only: joins that list, never the library.
    var listOnly: Bool?
    /// Stremio's compressed watched-episode bitfield, still undecoded. The worker turns it into
    /// `watched` once it has the show's episode list, then clears it.
    var stremioWatched: String?
    /// Pogdesign CAT gives a show's name and nothing else: matched by exact name across every
    /// year, still only when exactly one show has it (IMP-009). On a row with ids (TV Time,
    /// IMP-012), the same exact-name match is tried only when no provider knows the ids.
    var nameOnly: Bool?
    /// One episode CAT's calendar says this show airs. When several shows share the name, the
    /// one that airs that episode that day is the match (IMP-010).
    var airing: ImportAiring?
    /// Netflix names the episodes it played, it does not number them (IMP-018). Numbered into
    /// `watched` once the show is matched, then cleared.
    var namedEpisodes: [NamedEpisode]?
    /// A name-only row: the year it was first watched, so a title released later is not it.
    var notAfter: Int?
    /// The source's own words about the title (a Goodreads review, else its private notes,
    /// IMP-020). Fills empty notes only; never replaces what the library has.
    var notes: String?
    /// The source says the user owns a copy (Goodreads "Owned Copies", IMP-020). Only ever sets
    /// the flag, never clears it.
    var isOwned: Bool?

    var mediaRef: MediaRef {
        MediaRef(type: type, ids: ids, title: title, year: year)
    }

    /// Ticks or a reading position: the row is under way even when it names no status.
    var hasProgress: Bool {
        watched?.isEmpty == false || (mangaChapter ?? 0) > 0 || (mangaVolume ?? 0) > 0
    }
}

/// An episode and the day a calendar says it airs, `YYYY-MM-DD`.
struct ImportAiring: Codable, Sendable, Equatable {
    var season: Int
    var episode: Int
    var day: String
}

/// What a plan does with one row.
enum ImportOutcome: String, Codable, Sendable {
    case pending
    /// A new library item.
    case create
    /// An existing item gains a field it did not have (fill-empty only, IMP-004).
    case update
    /// Already on the shelf with nothing new, or a repeat of an earlier row.
    case skip
    /// No title could be matched; listed for the person to fix by hand.
    case unmatched
}

/// A stored row with its plan.
struct PlannedRow: Sendable, Equatable {
    var index: Int
    var row: ImportRow
    var outcome: ImportOutcome
    var reason: String?
    var titleID: TitleID?
}

/// The file does not look like the source it claims to be.
struct ImportFormatError: Error, Equatable {
    let message: String
}
