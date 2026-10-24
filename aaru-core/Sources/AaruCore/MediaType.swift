/// The kind of work a `Title` describes.
///
/// This is catalog vocabulary, not library vocabulary. A user's relationship to a
/// title is a `LibraryItem`.
public enum MediaType: String, Codable, Hashable, Sendable, CaseIterable {
    case movie
    case show
    case book
    /// A music album or EP: one MusicBrainz release group (MUS-001). Status only, no progress.
    case album
    /// Manga, manhwa, manhua and light novels: one AniList work of type MANGA (MNG-001).
    /// Progress is a chapter and a volume.
    case manga
}
