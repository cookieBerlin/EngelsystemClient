import Foundation
import SwiftData
import EngelsystemClientKit

@Observable
@MainActor
final class InstanceSetupViewModel {
    var name: String = ""
    var baseURL: String = ""
    var apiKey: String = ""

    var isTesting = false
    var errorMessage: String?

    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
            && !isTesting
    }

    /// Tests the connection against `/info` and, on success, creates a new `Instance`
    /// including a keychain entry. Returns `true` if the instance was saved.
    func testAndSave(in modelContext: ModelContext) async -> Bool {
        errorMessage = nil
        isTesting = true
        defer { isTesting = false }

        let instance = Instance(
            name: name.trimmingCharacters(in: .whitespaces),
            baseURL: baseURL.trimmingCharacters(in: .whitespaces),
            apiKeyKeychainRef: UUID().uuidString
        )

        let credential = EventCredential(baseURL: instance.apiBasePath, apiKey: apiKey)

        do {
            _ = try await apiClient.fetchInfo(credential)
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }

        let store: APIKeyStore = ICloudAvailability.isAvailable ? KeychainSyncStore() : LocalKeychainStore()
        do {
            try store.save(apiKey: apiKey, for: instance.apiKeyKeychainRef)
        } catch {
            errorMessage = "Could not save the API key to the keychain."
            return false
        }

        modelContext.insert(instance)
        return true
    }

    private static func message(for error: Error) -> String {
        guard let apiError = error as? APIError else {
            return "Connection failed: \(error.localizedDescription)"
        }
        switch apiError {
        case .unauthorized:
            return "API key is invalid or has expired."
        case .forbidden:
            return "No API access — the user needs the “API” or “Bureaucrat” group on this instance."
        case .notFound:
            return "The instance URL doesn't seem to provide an Engelsystem API (404 on /info)."
        case .invalidBaseURL:
            return "Please enter a valid server URL."
        case let .server(statusCode):
            return "Server responded with error \(statusCode)."
        case let .network(description):
            return "Connection failed: \(description)"
        case let .decoding(description):
            return "Could not read the API response: \(description)"
        }
    }
}
