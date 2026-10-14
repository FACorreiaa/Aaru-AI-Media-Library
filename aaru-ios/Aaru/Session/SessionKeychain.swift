import Foundation
import Security

/// The session token in the Keychain: it survives relaunch and never syncs off the device.
struct SessionKeychain {
    let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "com.fernandocorreia.aaru") {
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
