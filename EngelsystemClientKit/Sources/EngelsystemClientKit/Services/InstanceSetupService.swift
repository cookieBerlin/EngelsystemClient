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

    /// Tests a new API key against `instance`'s existing server and, on success,
    /// overwrites the stored key under the same `apiKeyKeychainRef` (unlike
    /// `createInstance`, no new `Instance`/keychain reference is created). Used when a
    /// key has expired or been revoked (`APIError.unauthorized`) — CLAUDE.md's "401 →
    /// back to Instance Setup" is realized as "back to Settings to fix the key" now
    /// that Settings/instance management exists.
    public func updateAPIKey(for instance: Instance, apiKey: String, store: APIKeyStore) async throws {
        let credential = EventCredential(baseURL: instance.apiBasePath, apiKey: apiKey)
        _ = try await apiClient.fetchInfo(credential)
        try store.save(apiKey: apiKey, for: instance.apiKeyKeychainRef)
    }

    /// Tests `name`/`baseURL` against `instance`'s existing API key (resolved by the
    /// caller via `InstanceCredentialResolver` — this never touches the Keychain
    /// itself) and, on success, updates `instance` in place. Re-tests even when only
    /// the name changed: cheap, and it doubles as a health check confirming the
    /// server/key combination is still valid. Mutating `instance` directly (rather
    /// than returning a value to apply) matches how sync services update existing
    /// `Cached*` models already fetched from a `ModelContext`. `userID` isn't part of
    /// the connection test (no `/users/{id}`-shaped endpoint is called here) — it's
    /// just saved alongside, see `Instance.userID`/`userReference`.
    public func updateServerDetails(for instance: Instance, name: String, baseURL: String, apiKey: String, userID: Int?) async throws {
        let credential = EventCredential(baseURL: Instance.apiBasePath(for: baseURL), apiKey: apiKey)
        _ = try await apiClient.fetchInfo(credential)
        instance.name = name
        instance.baseURL = baseURL
        instance.userID = userID
        instance.touch()
    }
}
