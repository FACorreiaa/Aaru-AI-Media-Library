import Foundation

/// The App Group container the app and the widget extension share.
///
/// The identifier comes from `APP_GROUP_ID` (Config/Base.xcconfig) via Info.plist,
/// so Beta and Release never read each other's data.
enum AppGroup {
    static let identifier = Bundle.main.object(forInfoDictionaryKey: "AaruAppGroupID") as? String ?? ""

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }

    private static let lastAppLaunchKey = "lastAppLaunch"

    /// Written by the app on launch, read by the widget: proof the container is shared.
    /// WID-001 replaces this with the real widget snapshot.
    static var lastAppLaunch: Date? {
        get { defaults?.object(forKey: lastAppLaunchKey) as? Date }
        set { defaults?.set(newValue, forKey: lastAppLaunchKey) }
    }
}
