import Foundation
import Security

/// The four SecItem calls the stores need, behind a protocol so every branch of the
/// stores' logic can be tested with a fake — the real implementation
/// (`SystemKeychainClient`) is a thin adapter that unit tests can't drive, since test
/// processes lack the keychain entitlements.
protocol KeychainClient {
    func add(_ query: [String: Any]) -> OSStatus
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, item: Any?)
    func delete(_ query: [String: Any]) -> OSStatus
}

/// Generic-password storage shared by `KeychainSyncStore` (iCloud-synced) and
/// `LocalKeychainStore` (device-local): they differ only in service name and the
/// `kSecAttrSynchronizable` flag.
struct KeychainItemStore {
    let service: String
    let synchronizable: Bool
    let client: KeychainClient

    func save(apiKey: String, for reference: String) throws {
        let data = Data(apiKey.utf8)
        var addQuery = baseQuery(for: reference)
        addQuery[kSecValueData as String] = data

        let status = client.add(addQuery)
        if status == errSecDuplicateItem {
            let updateStatus = client.update(baseQuery(for: reference), attributes: [kSecValueData as String: data])
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func loadAPIKey(for reference: String) throws -> String {
        var query = baseQuery(for: reference)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let result = client.copyMatching(query)
        guard result.status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(result.status)
        }
        guard let data = result.item as? Data, let apiKey = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedData
        }
        return apiKey
    }

    func deleteAPIKey(for reference: String) throws {
        let status = client.delete(baseQuery(for: reference))
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery(for reference: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference
        ]
        if synchronizable {
            query[kSecAttrSynchronizable as String] = true
        }
        return query
    }
}
