import Foundation
import Security

/// Thin adapter over the real `SecItem*` functions — kept in its own file because
/// test processes lack the keychain entitlements, so these lines can't run in unit
/// tests. All logic lives in `KeychainItemStore`, which is tested through a fake
/// `KeychainClient`. Excluded from the coverage gate (owner-approved 2026-10-12).
struct SystemKeychainClient: KeychainClient {
    func add(_ query: [String: Any]) -> OSStatus {
        SecItemAdd(query as CFDictionary, nil)
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, item: Any?) {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return (status, item)
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}
