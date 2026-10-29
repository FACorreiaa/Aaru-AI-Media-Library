import Foundation

/// A share link (SHR-002): `https://aaruapp.com/s/{code}`. The Apple apps claim that path as a
/// universal link, so this decides which links open the app's share sheet instead of the web page.
public enum ShareLinkCode {
    public static let hosts: Set<String> = ["aaruapp.com", "www.aaruapp.com", "beta.aaruapp.com"]

    /// The link's code, or nil for anything that is not a share link on Aaru's own hosts.
    public static func code(in url: URL) -> String? {
        guard url.scheme == "https", let host = url.host(), hosts.contains(host) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, parts[0] == "s",
              parts[1].wholeMatch(of: /[A-Za-z0-9]{1,32}/) != nil
        else { return nil }
        return parts[1]
    }
}

/// Saving a shared title on the way back from sign-in: once, and only when it is not theirs yet.
public enum ShareAutoAdd {
    public static func should(
        add: Bool, signedIn: Bool, isTitle: Bool, unavailable: Bool, alreadyInLibrary: Bool
    ) -> Bool {
        add && signedIn && isTitle && !unavailable && !alreadyInLibrary
    }
}

/// What a share link's sheet does when its preview did not load. Only an unknown code (404) says
/// the link doesn't work; offline, rate-limited or a server error offers a retry, and a failed
/// reload after a save keeps the card already on screen.
public enum ShareLoadFailure: Sendable, Equatable {
    case missing
    case retry
    case keep

    /// `status` is the HTTP status, nil when the request never got an answer.
    public static func after(status: Int?, showingContent: Bool) -> ShareLoadFailure {
        if showingContent {
            return .keep
        }
        return status == 404 ? .missing : .retry
    }
}
