import Foundation
import Security

/// Device-local fallback for when iCloud is disabled on the device
/// (see `ICloudAvailability`). Unlike `KeychainSyncStore`, without
/// `kSecAttrSynchronizable` and with its own service name, so both stores
/// can exist independently side by side without overwriting each other.
public struct LocalKeychainStore: APIKeyStore {
    private let service = "net.cuccato.engelsystem.apikey.local"

    public init() {}

    public func save(apiKey: String, for reference: String) throws {
        let data = Data(apiKey.utf8)
        let addQuery = baseQuery(for: reference).merging(
            [kSecValueData as String: data]
        ) { _, new in new }

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(
                baseQuery(for: reference) as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func loadAPIKey(for reference: String) throws -> String {
        var query = baseQuery(for: reference)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        guard let data = item as? Data, let apiKey = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedData
        }
        return apiKey
    }

    public func deleteAPIKey(for reference: String) throws {
        let status = SecItemDelete(baseQuery(for: reference) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery(for reference: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference
        ]
    }
}
