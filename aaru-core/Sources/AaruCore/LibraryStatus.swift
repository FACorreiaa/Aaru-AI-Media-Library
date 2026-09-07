/// How far the user has got with a title.
///
/// Consumption only. Ownership is `LibraryItem.isOwned` — do not overload this enum.
/// The raw values are a wire contract; changing one breaks stored client data.
public enum LibraryStatus: String, Codable, Hashable, Sendable, CaseIterable {
    case wishlist
    case inProgress = "in_progress"
    case finished
    case dropped
}
