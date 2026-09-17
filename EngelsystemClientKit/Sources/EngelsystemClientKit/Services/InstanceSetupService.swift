import Foundation

/// The "test a server/key, then save it" logic shared by the iOS app's InstanceSetup
/// feature and the Watch app's fallback entry form (see CLAUDE.md's sync strategy —
/// the Watch enters its own credentials locally rather than only relying on CloudKit).
public struct InstanceSetupService {
    private let apiClient: APIClient

    public init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    /// Tests the connection against `/info` and, on success, saves the API key to
    /// `store` and returns a new `Instance` ready to be inserted into a `ModelContext`.
    /// Throws the `APIError` from the connection test, or a `KeychainError` if saving
    /// the key fails — neither creates the `Instance`.
    public func createInstance(name: String, baseURL: String, apiKey: String, store: APIKeyStore, userID: Int? = nil) async throws -> Instance {
        let instance = Instance(name: name, baseURL: baseURL, apiKeyKeychainRef: UUID().uuidString, userID: userID)
        let credential = EventCredential(baseURL: instance.apiBasePath, apiKey: apiKey)

        _ = try await apiClient.fetchInfo(credential)
        try store.save(apiKey: apiKey, for: instance.apiKeyKeychainRef)

        return instance
    }

    /// Tests `name`/`baseURL`/`apiKey` together and, on success, updates `instance`'s
    /// name/baseURL/`userID` in place and (only if `newAPIKeyToStore` is non-nil)
    /// overwrites the keychain entry under the instance's existing `apiKeyKeychainRef`.
    /// Backs the single combined "Edit Instance" dialog (2026-09-17 multi-active-instance
    /// redesign, CLAUDE.md) that replaced the previously separate "Edit Name / Server"
    /// and "Update API Key" actions — callers resolve the *effective* key to test with
    /// themselves (the freshly typed one, or the existing one via
    /// `InstanceCredentialResolver` when the API Key field was left blank) and pass
    /// `newAPIKeyToStore` only when the user actually typed a replacement, so a
    /// pure name/server/userID edit never touches the Keychain at all. Re-tests even
    /// when only the name changed: cheap, and it doubles as a health check confirming
    /// the server/key combination is still valid. Mutating `instance` directly (rather
    /// than returning a value to apply) matches how sync services update existing
    /// `Cached*` models already fetched from a `ModelContext`. `userID` isn't part of
    /// the connection test (no `/users/{id}`-shaped endpoint is called here) — it's
    /// just saved alongside, see `Instance.userID`/`userReference`.
    public func updateInstance(
        for instance: Instance,
        name: String,
        baseURL: String,
        apiKey: String,
        newAPIKeyToStore: String?,
        userID: Int?,
        store: APIKeyStore
    ) async throws {
        let credential = EventCredential(baseURL: Instance.apiBasePath(for: baseURL), apiKey: apiKey)
        _ = try await apiClient.fetchInfo(credential)
        instance.name = name
        instance.baseURL = baseURL
        instance.userID = userID
        instance.touch()
        if let newAPIKeyToStore {
            try store.save(apiKey: newAPIKeyToStore, for: instance.apiKeyKeychainRef)
        }
    }
}
