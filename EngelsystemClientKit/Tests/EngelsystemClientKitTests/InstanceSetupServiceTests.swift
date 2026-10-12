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

@Test func instanceSetupServiceUpdatesInstanceAndKeychainWhenNewKeyProvided() async throws {
    let store = FakeAPIKeyStore()
    let instance = try await InstanceSetupService().createInstance(
        name: "Demo", baseURL: Instance.demoBaseURL, apiKey: "old-demo-key", store: store
    )
    let originalUpdatedAt = instance.updatedAt

    try await InstanceSetupService().updateInstance(
        for: instance,
        name: "Demo Renamed",
        baseURL: Instance.demoBaseURL,
        apiKey: "new-demo-key",
        newAPIKeyToStore: "new-demo-key",
        store: store
    )

    #expect(instance.name == "Demo Renamed")
    #expect(instance.baseURL == Instance.demoBaseURL)
    #expect(instance.updatedAt > originalUpdatedAt)
    // Same keychain reference is overwritten in place — no new Instance/reference created.
    #expect(try store.loadAPIKey(for: instance.apiKeyKeychainRef) == "new-demo-key")
}

/// The combined "Edit Instance" dialog leaves the API Key field blank to mean "keep the
/// existing key" (2026-09-17 multi-active-instance redesign, CLAUDE.md) — the caller
/// still resolves the *existing* key to test with, but passes `newAPIKeyToStore: nil` so
/// the Keychain entry is left completely untouched for a pure name/server edit.
@Test func instanceSetupServiceLeavesKeychainUntouchedWhenNoNewKeyProvided() async throws {
    let store = FakeAPIKeyStore()
    let instance = try await InstanceSetupService().createInstance(
        name: "Demo", baseURL: Instance.demoBaseURL, apiKey: "unchanged-demo-key", store: store
    )

    try await InstanceSetupService().updateInstance(
        for: instance,
        name: "Demo Renamed",
        baseURL: Instance.demoBaseURL,
        apiKey: "unchanged-demo-key",
        newAPIKeyToStore: nil,
        store: store
    )

    #expect(instance.name == "Demo Renamed")
    #expect(try store.loadAPIKey(for: instance.apiKeyKeychainRef) == "unchanged-demo-key")
}

@Test func instanceSetupServiceDoesNotUpdateInstanceWhenConnectionTestFails() async throws {
    let store = FakeAPIKeyStore()
    let instance = try await InstanceSetupService().createInstance(
        name: "Demo", baseURL: Instance.demoBaseURL, apiKey: "demo-key", store: store
    )

    await #expect(throws: APIError.invalidBaseURL) {
        try await InstanceSetupService().updateInstance(
            for: instance,
            name: "Should Not Save",
            baseURL: "http://%zz",
            apiKey: "demo-key",
            newAPIKeyToStore: "should-not-save-key",
                store: store
        )
    }

    #expect(instance.name == "Demo")
    #expect(instance.baseURL == Instance.demoBaseURL)
    #expect(try store.loadAPIKey(for: instance.apiKeyKeychainRef) == "demo-key")
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
