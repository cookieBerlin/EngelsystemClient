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
    public func createInstance(name: String, baseURL: String, apiKey: String, store: APIKeyStore) async throws -> Instance {
        let instance = Instance(name: name, baseURL: baseURL, apiKeyKeychainRef: UUID().uuidString)
        let credential = EventCredential(baseURL: instance.apiBasePath, apiKey: apiKey)

        _ = try await apiClient.fetchInfo(credential)
        try store.save(apiKey: apiKey, for: instance.apiKeyKeychainRef)

        return instance
    }
}
