import Foundation
import Security

/// Generic-password Keychain items scoped to the Hushtype service. An item lives either only on
/// this Mac or in iCloud Keychain (`synced`), where it reaches the user's other Macs.
enum Keychain {
    private static let service = "app.hushtype.api-keys"

    private static func query(_ account: String, synced: Bool) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account,
                                kSecAttrSynchronizable as String: synced]
        // iCloud Keychain items live in the data protection keychain.
        if synced { q[kSecUseDataProtectionKeychain as String] = true }
        return q
    }

    /// Reads from the preferred place first, falling back to the other one, so turning sync on or
    /// off never makes a saved key look missing.
    static func read(account: String, synced: Bool = false) -> String? {
        for place in [synced, !synced] {
            var q = query(account, synced: place)
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: AnyObject?
            if SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
               let data = result as? Data, let value = String(data: data, encoding: .utf8) {
                return value
            }
        }
        return nil
    }

    /// Saves the value. Returns false if macOS refused, which is what iCloud Keychain does in a
    /// build without the iCloud entitlement; the existing copy is left alone then.
    @discardableResult
    static func write(_ value: String, account: String, synced: Bool = false) -> Bool {
        let data = Data(value.utf8)
        let q = query(account, synced: synced)
        var status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = q
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { return false }
        // Once the key is in iCloud, drop the copy that was only on this Mac. The reverse isn't
        // done: deleting the iCloud copy would remove the key from the user's other Macs too.
        if synced { SecItemDelete(query(account, synced: false) as CFDictionary) }
        return true
    }

    /// Deletes this Mac's copy, and the iCloud copy too when `synced`.
    static func delete(account: String, synced: Bool = false) {
        SecItemDelete(query(account, synced: false) as CFDictionary)
        if synced { SecItemDelete(query(account, synced: true) as CFDictionary) }
    }
}
