import Foundation

/// SCR-005 configuration. MAL issues a client secret only to apps registered as "web"; one
/// registered as "other" has none, and every request then goes without it.
struct MALSettings: Sendable {
    static let authorizeURL = URL(string: "https://myanimelist.net/v1/oauth2/authorize")!
    static let tokenURL = URL(string: "https://myanimelist.net/v1/oauth2/token")!
    static let apiURL = URL(string: "https://api.myanimelist.net/v2")!

    var clientID: String
    var clientSecret: String?
    /// Must match the MAL app's App Redirect URL exactly. `https://` on Aaru's own API host.
    var redirectURI: URL
    /// Where a finished connect may send the browser: the apps' URL scheme and the web origin.
    var returnPrefixes: [String]
    var tokenCipher: TokenCipher

    func allowsReturn(to url: String) -> Bool {
        returnPrefixes.contains { url.hasPrefix($0) }
    }
}
