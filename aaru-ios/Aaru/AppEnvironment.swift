import Foundation

/// Build-time settings, set per configuration in Config/*.xcconfig.
enum AppEnvironment {
    /// The `/v1` API host. Beta and Release both point at production.
    static let apiBaseURL: URL? = (Bundle.main.object(forInfoDictionaryKey: "AaruAPIBaseURL") as? String)
        .flatMap(URL.init(string:))

    /// The Google OAuth client (iOS type) for this bundle id. Nil hides Sign in with Google.
    static let googleClientID: String? = (Bundle.main.object(forInfoDictionaryKey: "AaruGoogleClientID") as? String)
        .flatMap { $0.isEmpty ? nil : $0 }

    static var channel: String {
        #if DEBUG
            "Debug"
        #elseif BETA
            "Beta"
        #else
            "Release"
        #endif
    }
}
