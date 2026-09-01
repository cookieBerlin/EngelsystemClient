import Foundation

public enum InstanceCredentialError: Error {
    case apiKeyNotFound
}

/// Looks up the API key for an `Instance` from whichever keychain store it was
/// saved in (iCloud-synced or local fallback — which one isn't persisted on the
/// `Instance` itself, so both are tried).
public struct InstanceCredentialResolver {
    public init() {}

    public func credential(for instance: Instance) throws -> EventCredential {
        if let apiKey = try? KeychainSyncStore().loadAPIKey(for: instance.apiKeyKeychainRef) {
            return EventCredential(baseURL: instance.apiBasePath, apiKey: apiKey)
        }
        if let apiKey = try? LocalKeychainStore().loadAPIKey(for: instance.apiKeyKeychainRef) {
            return EventCredential(baseURL: instance.apiBasePath, apiKey: apiKey)
        }
        throw InstanceCredentialError.apiKeyNotFound
    }
}
