import Observation

/// A notification the user tapped, waiting for the signed-in app to open its title. It outlives
/// a cold launch: the tap can arrive before any view is on screen.
@MainActor
@Observable
final class PushInbox {
    static let shared = PushInbox()

    /// The library item to open, from the alert's `libraryItemId`.
    var libraryItemID: String?
}
