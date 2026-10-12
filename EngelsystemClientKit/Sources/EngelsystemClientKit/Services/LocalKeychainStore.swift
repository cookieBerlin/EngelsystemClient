import Foundation

/// Device-local fallback for when iCloud is disabled on the device
/// (see `ICloudAvailability`). Unlike `KeychainSyncStore`, without
/// `kSecAttrSynchronizable` and with its own service name, so both stores
/// can exist independently side by side without overwriting each other.
public struct LocalKeychainStore: APIKeyStore {
    private let store: KeychainItemStore

    public init() {
        self.init(client: SystemKeychainClient())
    }

    init(client: KeychainClient) {
        store = KeychainItemStore(service: "net.cuccato.engelsystem.de.apikey.local", synchronizable: false, client: client)
    }

    public func save(apiKey: String, for reference: String) throws {
        try store.save(apiKey: apiKey, for: reference)
    }

    public func loadAPIKey(for reference: String) throws -> String {
        try store.loadAPIKey(for: reference)
    }

    public func deleteAPIKey(for reference: String) throws {
        try store.deleteAPIKey(for: reference)
    }
}
