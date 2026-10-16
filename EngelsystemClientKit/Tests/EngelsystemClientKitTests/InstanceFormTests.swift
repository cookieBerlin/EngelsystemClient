import Foundation
import Testing
@testable import EngelsystemClientKit

struct InstanceFormTests {
    @Test func onlyDemoAddressesNeedNoKey() {
        #expect(InstanceForm.requiresAPIKey(address: "https://engelsystem.example.org"))
        #expect(InstanceForm.requiresAPIKey(address: ""))
        #expect(!InstanceForm.requiresAPIKey(address: "demo://engelsystem.local"))
        #expect(!InstanceForm.requiresAPIKey(address: "  demo://congress.local "))
        #expect(!InstanceForm.requiresAPIKey(address: "demo://anything.local"))
    }

    @Test func theEffectiveKeyIsTheTypedOneOrTheDemoKey() {
        #expect(InstanceForm.effectiveAPIKey(address: "https://a.test", typed: "  secret ") == "secret")
        #expect(InstanceForm.effectiveAPIKey(address: "https://a.test", typed: "") == "")
        #expect(InstanceForm.effectiveAPIKey(address: "demo://engelsystem.local", typed: "ignored") == "demo")
        #expect(InstanceForm.effectiveAPIKey(address: "demo://engelsystem.local", typed: "") == InstanceForm.demoAPIKey)
        #expect(!InstanceForm.demoKeyHint.isEmpty)
    }

    @Test func savingNeedsANameAndAnAddressOnly() {
        #expect(InstanceForm.canSave(name: "Home", address: "https://a.test"))
        #expect(!InstanceForm.canSave(name: "  ", address: "https://a.test"))
        #expect(!InstanceForm.canSave(name: "Home", address: ""))
    }

    @Test func changesAreFoundInNameAddressAndKey() {
        func changed(
            name: String = "Home", address: String = "https://a.test", key: String = ""
        ) -> Bool {
            InstanceForm.hasChanges(
                savedName: "Home", savedAddress: "https://a.test", name: name, address: address, typedKey: key)
        }
        #expect(!changed())
        #expect(!changed(name: " Home "))
        #expect(!changed(address: "https://a.test/")) // the trailing slash is not a change
        #expect(changed(name: "Congress"))
        #expect(changed(address: "https://b.test"))
        #expect(changed(key: "new"))
        #expect(!changed(key: "   "))
    }

    @MainActor
    @Test func applyingChangesNeverTestsTheConnectionAndOnlyStoresATypedKey() throws {
        final class Store: APIKeyStore, @unchecked Sendable {
            var saved: [String: String] = [:]
            func save(apiKey: String, for reference: String) throws { saved[reference] = apiKey }
            func loadAPIKey(for reference: String) throws -> String { saved[reference] ?? "" }
            func deleteAPIKey(for reference: String) throws {}
        }
        let store = Store()
        let instance = Instance(name: "Old", baseURL: "https://old.test", apiKeyKeychainRef: "ref")
        let service = InstanceSetupService()

        try service.applyChanges(to: instance, name: "New", baseURL: "https://new.test", newAPIKeyToStore: nil, store: store)
        #expect(instance.name == "New" && instance.baseURL == "https://new.test")
        #expect(store.saved.isEmpty)

        try service.applyChanges(to: instance, name: "New", baseURL: "https://new.test", newAPIKeyToStore: "key", store: store)
        #expect(store.saved["ref"] == "key")
    }
}
