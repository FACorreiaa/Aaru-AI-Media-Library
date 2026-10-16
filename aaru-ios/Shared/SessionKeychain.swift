import Foundation
import Security

/// The session token in the Keychain: it survives relaunch and never syncs off the device.
/// Compiled into the app and the widget extension. Both name the app's bundle id as the service
/// and share the app's keychain access group, so a widget's intent acts as the signed-in user.
struct SessionKeychain {
    let service: String

    /// The app's bundle id, also from inside the extension (whose own id ends in `.widgets`).
    static var appService: String {
        Bundle.main.object(forInfoDictionaryKey: "AaruAppBundleID") as? String
            ?? Bundle.main.bundleIdentifier ?? "com.fernandocorreia.aaru"
    }

    init(service: String = SessionKeychain.appService) {
        self.service = service
    }

    private var item: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "session",
            // The iOS-style keychain on macOS too, so both platforms behave the same.
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    func read() -> String? {
        var query = item
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(bytes: data, encoding: .utf8)
    }

    func save(_ token: String) {
        delete()
        var attributes = item
        attributes[kSecValueData as String] = Data(token.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func delete() {
        SecItemDelete(item as CFDictionary)
    }
}
