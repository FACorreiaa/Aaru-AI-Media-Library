/// How far the user has got with a title.
///
/// Consumption only. Ownership is `LibraryItem.isOwned` — do not overload this enum.
/// The raw values are a wire contract; changing one breaks stored client data.
///
/// `onHold` is paused on purpose (owner, 2026-10-25, LIB-007). It ranks with `inProgress` for
/// imports, is left off Now, Up Next, Tonight and the week, and a live tick moves it back to
/// `inProgress`. The UI label is "On hold" for every kind.
public enum LibraryStatus: String, Codable, Hashable, Sendable, CaseIterable {
    case wishlist
    case inProgress = "in_progress"
    case onHold = "on_hold"
    case finished
    case dropped
}
