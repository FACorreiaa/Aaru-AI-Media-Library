/// The kind of work a `Title` describes.
///
/// This is catalog vocabulary, not library vocabulary. A user's relationship to a
/// title is a `LibraryItem`.
public enum MediaType: String, Codable, Hashable, Sendable, CaseIterable {
    case movie
    case show
    case book
}
