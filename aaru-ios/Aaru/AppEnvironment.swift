import Foundation

/// Build-time settings, set per configuration in Config/*.xcconfig.
enum AppEnvironment {
    /// The `/v1` API host. Beta and Release both point at production.
    static let apiBaseURL: URL? = (Bundle.main.object(forInfoDictionaryKey: "AaruAPIBaseURL") as? String)
        .flatMap(URL.init(string:))

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
