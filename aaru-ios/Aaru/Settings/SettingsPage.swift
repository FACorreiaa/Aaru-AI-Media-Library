import SwiftUI

/// Settings' eight pages (DESIGN.md §18), in order. The raw value is the web's slug, so
/// `aaru://settings/<slug>` and `/app/settings/<slug>` name the same page.
enum SettingsPage: String, CaseIterable, Identifiable, Hashable {
    case account
    case friends
    case notifications
    case imports = "import"
    case connections
    case data
    case about
    case delete

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .account: "Account"
        case .friends: "Friends & privacy"
        case .notifications: "Notifications"
        case .imports: "Import"
        case .connections: "Connections"
        case .data: "Your data"
        case .about: "About"
        case .delete: "Delete account"
        }
    }

    var symbol: String {
        switch self {
        case .account: "person.crop.circle.fill"
        case .friends: "person.2.fill"
        case .notifications: "bell.badge.fill"
        case .imports: "tray.and.arrow.down.fill"
        case .connections: "app.connected.to.app.below.fill"
        case .data: "externaldrive.fill"
        case .about: "info"
        case .delete: "trash.fill"
        }
    }

    /// The tinted square behind the symbol, as in the system Settings, in Aaru's own four: the
    /// accent for the account, gold for what brings titles in, danger for what removes them,
    /// muted for the rest. The glyph on every one is `onAccent`.
    var tint: Color {
        switch self {
        case .account: Color(.accent)
        case .imports, .connections: Color(.gold)
        case .delete: Color(.danger)
        case .friends, .notifications, .data, .about: Color(.muted)
        }
    }

    /// The Mac's Settings scene has seven panes: Delete account sits at the bottom of Account.
    static let macPanes: [SettingsPage] = [.account, .friends, .notifications, .imports, .connections, .data, .about]

    var macPane: SettingsPage {
        self == .delete ? .account : self
    }
}

/// Where Settings' stack goes: a page, an import job opened from Import, or History.
enum SettingsRoute: Hashable {
    case page(SettingsPage)
    case job(String)
    case history
}
