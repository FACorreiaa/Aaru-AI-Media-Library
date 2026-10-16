import Foundation

/// The App Group container the app and the widget extension share.
///
/// The identifier comes from `APP_GROUP_ID` (Config/Base.xcconfig) via Info.plist,
/// so Beta and Release never read each other's data.
enum AppGroup {
    static let identifier = Bundle.main.object(forInfoDictionaryKey: "AaruAppGroupID") as? String ?? ""
}
