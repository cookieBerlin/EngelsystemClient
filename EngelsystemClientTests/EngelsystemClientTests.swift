//
//  EngelsystemClientTests.swift
//  EngelsystemClientTests
//
//  Created by Angelo Cuccato on 31.08.26.
//

import Foundation
import Testing
import SwiftData
import EngelsystemClientKit
@testable import EngelsystemClient

/// Regression coverage for the 2026-09-16 bug: a user reported that a manually
/// re-entered `Instance.userID` reverted to `nil` after rebuilding the app from
/// Xcode. Root cause: no production code path ever called `modelContext.save()`
/// explicitly, relying entirely on SwiftData's autosave — which fires on
/// app-lifecycle events (e.g. resigning active) that a debug rebuild-and-relaunch
/// skips entirely, since Xcode kills the old process directly instead of
/// backgrounding it. Fixed by having `EditInstanceViewModel.save` (and the
/// equivalent create/delete flows) explicitly call `modelContext.save()`. This test
/// proves the fix by reloading from a brand-new `ModelContainer` backed by the same
/// on-disk store, rather than re-reading the same in-memory `ModelContext` — the
/// latter would pass even without an explicit save, since the edit is visible
/// in-memory regardless of whether it was ever flushed to disk.
struct EditInstanceViewModelPersistenceTests {
    @Test @MainActor func saveExplicitlyPersistsUserIDAcrossAFreshModelContainerLoad() async throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("EditInstanceViewModelPersistenceTests-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
        }
        let configuration = ModelConfiguration(schema: Schema([Instance.self]), url: storeURL, cloudKitDatabase: .none)

        let container = try ModelContainer(for: Instance.self, configurations: configuration)
        let context = ModelContext(container)

        let instance = Instance(name: "Demo", baseURL: Instance.demoBaseURL, apiKeyKeychainRef: UUID().uuidString)
        context.insert(instance)
        try context.save()

        let keyStore = LocalKeychainStore()
        try keyStore.save(apiKey: "demo", for: instance.apiKeyKeychainRef)
        defer { try? keyStore.deleteAPIKey(for: instance.apiKeyKeychainRef) }

        let viewModel = EditInstanceViewModel(instance: instance)
        viewModel.userIDText = "42"
        let succeeded = await viewModel.save(instance: instance, in: context)
        #expect(succeeded)

        // Simulate the rebuild-and-relaunch scenario: a fresh container/context
        // reading the same file, not the `context` the edit was made through.
        let reloadedContainer = try ModelContainer(for: Instance.self, configurations: configuration)
        let reloadedContext = ModelContext(reloadedContainer)
        let reloadedInstance = try #require(try reloadedContext.fetch(FetchDescriptor<Instance>()).first)
        #expect(reloadedInstance.userID == 42)
    }
}

/// Coverage for the combined "Edit Instance" dialog's API Key field (2026-09-17
/// multi-active-instance redesign, CLAUDE.md): leaving it blank must keep the existing
/// key untouched, typing a new one must overwrite it. `InstanceSetupServiceTests` (Kit)
/// already covers this at the service layer in isolation; these two exercise the
/// `EditInstanceViewModel` on top, seeding *both* Keychain stores identically so the
/// assertions hold regardless of `ICloudAvailability.isAvailable` in the test
/// environment (the view model always mirrors a freshly typed key into both stores, and
/// never touches either when the field is left blank).
struct EditInstanceViewModelAPIKeyTests {
    @MainActor
    private func makeInstanceWithSeededKey(_ key: String) throws -> (Instance, ModelContext) {
        let configuration = ModelConfiguration(schema: Schema([Instance.self]), isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Instance.self, configurations: configuration)
        let context = ModelContext(container)
        let instance = Instance(name: "Demo", baseURL: Instance.demoBaseURL, apiKeyKeychainRef: UUID().uuidString)
        context.insert(instance)
        try KeychainSyncStore().save(apiKey: key, for: instance.apiKeyKeychainRef)
        try LocalKeychainStore().save(apiKey: key, for: instance.apiKeyKeychainRef)
        return (instance, context)
    }

    @Test @MainActor func blankAPIKeyFieldLeavesTheExistingKeyUnchanged() async throws {
        let (instance, context) = try makeInstanceWithSeededKey("original-key")
        defer { try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef); try? KeychainSyncStore().deleteAPIKey(for: instance.apiKeyKeychainRef) }

        let viewModel = EditInstanceViewModel(instance: instance)
        viewModel.apiKey = ""
        let succeeded = await viewModel.save(instance: instance, in: context)

        #expect(succeeded)
        #expect(try LocalKeychainStore().loadAPIKey(for: instance.apiKeyKeychainRef) == "original-key")
    }

    @Test @MainActor func nonBlankAPIKeyFieldOverwritesTheExistingKey() async throws {
        let (instance, context) = try makeInstanceWithSeededKey("original-key")
        defer { try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef); try? KeychainSyncStore().deleteAPIKey(for: instance.apiKeyKeychainRef) }

        let viewModel = EditInstanceViewModel(instance: instance)
        viewModel.apiKey = "replacement-key"
        let succeeded = await viewModel.save(instance: instance, in: context)

        #expect(succeeded)
        #expect(try LocalKeychainStore().loadAPIKey(for: instance.apiKeyKeychainRef) == "replacement-key")
    }
}

struct SyncErrorMapperTests {
    @Test func isUnauthorizedIsTrueOnlyForAPIErrorUnauthorized() {
        #expect(SyncErrorMapper.isUnauthorized(APIError.unauthorized))
        #expect(!SyncErrorMapper.isUnauthorized(APIError.forbidden))
        #expect(!SyncErrorMapper.isUnauthorized(APIError.notFound))
        #expect(!SyncErrorMapper.isUnauthorized(InstanceCredentialError.apiKeyNotFound))
    }

    @Test func messageMapsInstanceCredentialAndKeychainErrorsToReadableText() {
        #expect(SyncErrorMapper.message(for: InstanceCredentialError.apiKeyNotFound).contains("Settings"))
        #expect(SyncErrorMapper.message(for: KeychainError.unexpectedData).contains("keychain"))
        #expect(SyncErrorMapper.message(for: APIError.forbidden) == APIError.forbidden.userMessage)
    }

    @Test func isCancellationIsTrueOnlyForCancellationError() {
        #expect(SyncErrorMapper.isCancellation(CancellationError()))
        #expect(!SyncErrorMapper.isCancellation(APIError.network("offline")))
        #expect(!SyncErrorMapper.isCancellation(InstanceCredentialError.apiKeyNotFound))
    }
}
