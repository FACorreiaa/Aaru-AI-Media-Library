import AaruCore
import Foundation

/// A share link (SHR-002): `https://aaruapp.com/s/{code}`, opened from Messages or anywhere else.
/// Named `SharedLink` because SwiftUI already has a `ShareLink`. Unlike an invite it opens signed
/// out too: whoever taps it just sees what was shared.
struct SharedLink: Identifiable, Equatable {
    let code: String
    /// Save the shared title once this sheet opens: the person asked for it before signing in.
    var add = false

    var id: String {
        code
    }

    init?(_ url: URL) {
        guard let code = ShareLinkCode.code(in: url) else { return nil }
        self.code = code
    }

    /// The same link, asking to save its title once the person has signed in.
    func addingTitle() -> SharedLink {
        var link = self
        link.add = true
        return link
    }
}
