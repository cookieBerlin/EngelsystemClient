import Foundation

/// Persists API keys with iCloud sync (`kSecAttrSynchronizable`), shared between
/// the iOS and Watch apps via the Keychain Sharing access group
/// `$(AppIdentifierPrefix)net.cuccato.engelsystem.de.shared` from both targets' entitlements.
/// The access group is deliberately not set explicitly here: Xcode only resolves
/// `$(AppIdentifierPrefix)` at build/signing time based on the team certificate,
/// and SecItem calls without `kSecAttrAccessGroup` automatically use the
/// (single) group listed in the entitlements.
public struct KeychainSyncStore: APIKeyStore {
    private let store: KeychainItemStore

    public init() {
        self.init(client: SystemKeychainClient())
    }

    init(client: KeychainClient) {
        store = KeychainItemStore(service: "net.cuccato.engelsystem.de.apikey.synced", synchronizable: true, client: client)
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
