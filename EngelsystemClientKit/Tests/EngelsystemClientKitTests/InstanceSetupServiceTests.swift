import Foundation
import Testing
@testable import EngelsystemClientKit

private final class FakeAPIKeyStore: APIKeyStore {
    private(set) var savedKeys: [String: String] = [:]

    func save(apiKey: String, for reference: String) throws {
        savedKeys[reference] = apiKey
    }

    func loadAPIKey(for reference: String) throws -> String {
        guard let apiKey = savedKeys[reference] else { throw KeychainError.unexpectedData }
        return apiKey
    }

    func deleteAPIKey(for reference: String) throws {
        savedKeys.removeValue(forKey: reference)
    }
}

@Test func instanceSetupServiceCreatesInstanceAndSavesKeyForDemoServer() async throws {
    let store = FakeAPIKeyStore()
    let instance = try await InstanceSetupService().createInstance(
        name: "Demo",
        baseURL: Instance.demoBaseURL,
        apiKey: "demo",
        store: store
    )

    #expect(instance.name == "Demo")
    #expect(instance.isDemo)
    #expect(try store.loadAPIKey(for: instance.apiKeyKeychainRef) == "demo")
}

@Test func instanceSetupServiceUpdatesAPIKeyForExistingInstance() async throws {
    let store = FakeAPIKeyStore()
    let instance = try await InstanceSetupService().createInstance(
        name: "Demo", baseURL: Instance.demoBaseURL, apiKey: "old-demo-key", store: store
    )

    try await InstanceSetupService().updateAPIKey(for: instance, apiKey: "new-demo-key", store: store)

    // Same keychain reference is overwritten in place — no new Instance/reference created.
    #expect(try store.loadAPIKey(for: instance.apiKeyKeychainRef) == "new-demo-key")
}

@Test func instanceSetupServiceDoesNotSaveKeyWhenConnectionTestFails() async throws {
    // Bad percent-encoding makes URL(string:) return nil, which APIClient maps to
    // .invalidBaseURL — deterministic and offline (see apiClientRejectsEmptyBaseURLForNonDemoInstance
    // in EngelsystemClientKitTests.swift for the same guard exercised directly against APIClient).
    let store = FakeAPIKeyStore()
    await #expect(throws: APIError.invalidBaseURL) {
        _ = try await InstanceSetupService().createInstance(
            name: "Broken",
            baseURL: "http://%zz",
            apiKey: "some-key",
            store: store
        )
    }
    #expect(store.savedKeys.isEmpty)
}
