import Foundation
import Security
import Testing
@testable import EngelsystemClientKit

private final class FakeKeychain: KeychainClient, @unchecked Sendable {
    var items: [String: Data] = [:]
    var addStatus: OSStatus?
    var updateStatus: OSStatus?
    var copyStatus: OSStatus?
    var deleteStatus: OSStatus?
    var copiedItem: Any??
    var queries: [[String: Any]] = []

    private func key(_ query: [String: Any]) -> String {
        "\(query[kSecAttrService as String] ?? ""):\(query[kSecAttrAccount as String] ?? "")"
    }

    func add(_ query: [String: Any]) -> OSStatus {
        queries.append(query)
        if let addStatus { return addStatus }
        if items[key(query)] != nil { return errSecDuplicateItem }
        items[key(query)] = query[kSecValueData as String] as? Data
        return errSecSuccess
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        if let updateStatus { return updateStatus }
        items[key(query)] = attributes[kSecValueData as String] as? Data
        return errSecSuccess
    }

    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, item: Any?) {
        queries.append(query)
        if let copyStatus { return (copyStatus, nil) }
        if let copiedItem { return (errSecSuccess, copiedItem) }
        guard let data = items[key(query)] else { return (errSecItemNotFound, nil) }
        return (errSecSuccess, data)
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        if let deleteStatus { return deleteStatus }
        return items.removeValue(forKey: key(query)) == nil ? errSecItemNotFound : errSecSuccess
    }
}

struct KeychainStoreTests {
    private func localStore(_ fake: FakeKeychain) -> KeychainItemStore {
        KeychainItemStore(service: "svc", synchronizable: false, client: fake)
    }

    @Test func saveThenLoadRoundTrips() throws {
        let fake = FakeKeychain()
        let store = localStore(fake)
        try store.save(apiKey: "abc", for: "ref")
        #expect(try store.loadAPIKey(for: "ref") == "abc")
    }

    @Test func savingAgainUpdatesTheExistingItem() throws {
        let fake = FakeKeychain()
        let store = localStore(fake)
        try store.save(apiKey: "old", for: "ref")
        try store.save(apiKey: "new", for: "ref")
        #expect(try store.loadAPIKey(for: "ref") == "new")
    }

    @Test func aFailingUpdateThrowsItsStatus() {
        let fake = FakeKeychain()
        fake.items["svc:ref"] = Data("x".utf8)
        fake.updateStatus = errSecAuthFailed
        #expect(throws: KeychainError.self) { try localStore(fake).save(apiKey: "k", for: "ref") }
    }

    @Test func aFailingAddThrowsItsStatus() {
        let fake = FakeKeychain()
        fake.addStatus = errSecMissingEntitlement
        #expect(throws: KeychainError.self) { try localStore(fake).save(apiKey: "k", for: "ref") }
    }

    @Test func loadingAMissingItemThrows() {
        #expect(throws: KeychainError.self) { try localStore(FakeKeychain()).loadAPIKey(for: "nope") }
    }

    @Test func loadingNonTextDataThrowsUnexpectedData() {
        let fake = FakeKeychain()
        fake.copiedItem = .some(Data([0xFF, 0xFE]))
        #expect(throws: KeychainError.self) { try localStore(fake).loadAPIKey(for: "ref") }
        fake.copiedItem = .some("not data")
        #expect(throws: KeychainError.self) { try localStore(fake).loadAPIKey(for: "ref") }
    }

    @Test func deleteRemovesAndToleratesAMissingItem() throws {
        let fake = FakeKeychain()
        let store = localStore(fake)
        try store.save(apiKey: "abc", for: "ref")
        try store.deleteAPIKey(for: "ref")
        #expect(fake.items.isEmpty)
        try store.deleteAPIKey(for: "ref")
    }

    @Test func aFailingDeleteThrows() {
        let fake = FakeKeychain()
        fake.deleteStatus = errSecInteractionNotAllowed
        #expect(throws: KeychainError.self) { try localStore(fake).deleteAPIKey(for: "ref") }
    }

    @Test func onlyTheSyncedStoreMarksItemsSynchronizable() throws {
        let synced = FakeKeychain()
        let local = FakeKeychain()
        try KeychainSyncStore(client: synced).save(apiKey: "a", for: "r")
        try LocalKeychainStore(client: local).save(apiKey: "a", for: "r")
        #expect(synced.queries[0][kSecAttrSynchronizable as String] as? Bool == true)
        #expect(local.queries[0][kSecAttrSynchronizable as String] == nil)
        #expect(synced.queries[0][kSecAttrService as String] as? String == "net.cuccato.engelsystem.de.apikey.synced")
        #expect(local.queries[0][kSecAttrService as String] as? String == "net.cuccato.engelsystem.de.apikey.local")
    }

    @Test func bothPublicStoresDelegateEveryOperation() throws {
        for store in [KeychainSyncStore(client: FakeKeychain()) as APIKeyStore, LocalKeychainStore(client: FakeKeychain())] {
            try store.save(apiKey: "k", for: "r")
            #expect(try store.loadAPIKey(for: "r") == "k")
            try store.deleteAPIKey(for: "r")
        }
    }

    @Test func publicInitializersBuildTheSystemBackedStores() {
        _ = KeychainSyncStore()
        _ = LocalKeychainStore()
    }
}
