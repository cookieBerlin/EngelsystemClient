import Foundation

public enum InstanceCredentialError: Error {
    case apiKeyNotFound
}

/// Looks up the API key for an `Instance` from whichever keychain store it was
/// saved in (iCloud-synced or local fallback — which one isn't persisted on the
/// `Instance` itself, so both are tried, in order).
public struct InstanceCredentialResolver {
    private let stores: [APIKeyStore]

    public init() {
        self.init(stores: [KeychainSyncStore(), LocalKeychainStore()])
    }

    init(stores: [APIKeyStore]) {
        self.stores = stores
    }

    public func credential(for instance: Instance) throws -> EventCredential {
        for store in stores {
            if let apiKey = try? store.loadAPIKey(for: instance.apiKeyKeychainRef) {
                return EventCredential(baseURL: instance.apiBasePath, apiKey: apiKey)
            }
        }
        throw InstanceCredentialError.apiKeyNotFound
    }
}
