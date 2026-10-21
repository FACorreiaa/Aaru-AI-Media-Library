import SwiftUI

/// Light, dark or the system's, per device (the web keeps its own per browser). Stored with
/// `@AppStorage(Appearance.storageKey)` and applied once at the root of each window.
enum Appearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "appearance"

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `nil` follows the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// The Settings row: a menu picker, as in the system's own Settings.
struct AppearancePicker: View {
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system

    var body: some View {
        Picker(selection: $appearance) {
            ForEach(Appearance.allCases) { option in
                Text(option.label).tag(option)
            }
        } label: {
            SettingsRowLabel("Appearance", systemImage: "circle.lefthalf.filled", tint: .indigo)
        }
    }
}

private struct AppliesAppearance: ViewModifier {
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system

    func body(content: Content) -> some View {
        content.preferredColorScheme(appearance.colorScheme)
    }
}

extension View {
    /// The device's chosen appearance, for the root of a window.
    func appliesAppearance() -> some View {
        modifier(AppliesAppearance())
    }
}
