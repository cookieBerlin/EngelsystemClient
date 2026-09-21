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
    #expect(instance.selfReferenceWorks)
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
        userID: 42,
        store: store
    )

    #expect(instance.name == "Demo Renamed")
    #expect(instance.baseURL == Instance.demoBaseURL)
    // Demo credentials always report selfReferenceWorks == true, so updateInstance
    // force-clears the passed-in userID regardless — see
    // instanceSetupServiceClearsUserIDWhenSelfReferenceWorks below for the dedicated
    // coverage of that behavior; this test's own focus is name/keychain/timestamp.
    #expect(instance.userID == nil)
    #expect(instance.updatedAt > originalUpdatedAt)
    // Same keychain reference is overwritten in place — no new Instance/reference created.
    #expect(try store.loadAPIKey(for: instance.apiKeyKeychainRef) == "new-demo-key")
}

/// The combined "Edit Instance" dialog leaves the API Key field blank to mean "keep the
/// existing key" (2026-09-17 multi-active-instance redesign, CLAUDE.md) — the caller
/// still resolves the *existing* key to test with, but passes `newAPIKeyToStore: nil` so
/// the Keychain entry is left completely untouched for a pure name/server/userID edit.
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
        userID: 42,
        store: store
    )

    #expect(instance.name == "Demo Renamed")
    // Demo credentials always report selfReferenceWorks == true, so the passed-in
    // userID is force-cleared — see instanceSetupServiceClearsUserIDWhenSelfReferenceWorks.
    #expect(instance.userID == nil)
    #expect(try store.loadAPIKey(for: instance.apiKeyKeychainRef) == "unchanged-demo-key")
}

/// 2026-09-21, user-requested: editing an instance and finding `self` now works
/// should actually remove a now-stale User ID **when Save is pressed** (not
/// immediately when just "Test Connection" is pressed — that only previews). Proves
/// `updateInstance` clears a previously-set `userID` even though the caller passed a
/// non-nil value, as long as the (re-probed) `selfReferenceWorks` says it's unneeded.
/// Only `updateInstance` (the "Edit Instance" dialog) enforces this — `createInstance`
/// still stores whatever `userID` it's given as-is, since Setup already only ever
/// passes a non-nil one once its own explicit "Test Connection" step determined it's
/// actually needed (see `InstanceSetupViewModel`/`WatchSetupViewModel`), so there's no
/// equivalent "stale value from before" case to guard against there.
@Test func instanceSetupServiceClearsUserIDWhenSelfReferenceWorks() async throws {
    let store = FakeAPIKeyStore()
    let instance = try await InstanceSetupService().createInstance(
        name: "Demo", baseURL: Instance.demoBaseURL, apiKey: "demo-key", store: store
    )
    // Simulate a pre-existing instance that somehow still has a stale userID (e.g. set
    // before this feature existed, or a server that later got fixed) and confirm a
    // save clears it rather than keeping it.
    instance.userID = 42

    try await InstanceSetupService().updateInstance(
        for: instance,
        name: "Demo",
        baseURL: Instance.demoBaseURL,
        apiKey: "demo-key",
        newAPIKeyToStore: nil,
        userID: 42, // caller still passes the stale form value...
        store: store
    )

    #expect(instance.selfReferenceWorks)
    #expect(instance.userID == nil) // ...but it's discarded since selfReferenceWorks is true
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
            userID: 99,
            store: store
        )
    }

    #expect(instance.name == "Demo")
    #expect(instance.baseURL == Instance.demoBaseURL)
    #expect(instance.userID == nil)
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
