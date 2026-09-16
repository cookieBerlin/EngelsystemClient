import Foundation
import SwiftData
import Testing
@testable import EngelsystemClientKit

@MainActor
private func makeInMemoryContext() throws -> ModelContext {
    let schema = Schema([
        Instance.self, CachedShift.self, CachedNews.self, CachedUser.self,
        CachedWorklog.self, CachedAngelTypeMembership.self,
    ])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [config])
    return ModelContext(container)
}

private let demoCredential = EventCredential(baseURL: Instance.demoBaseURL + "/api/v0-beta", apiKey: "demo")

@Test @MainActor func shiftSyncServiceInsertsAndUpdatesWithoutDuplicating() async throws {
    let context = try makeInMemoryContext()
    let instance = Instance(name: "Demo", baseURL: Instance.demoBaseURL, apiKeyKeychainRef: "ref")
    context.insert(instance)

    let service = ShiftSyncService()
    let first = try await service.sync(instance: instance, credential: demoCredential, in: context)
    #expect(first.count == 2)
    #expect(try context.fetch(FetchDescriptor<CachedShift>()).count == 2)

    // Syncing again must update the existing rows in place, not duplicate them.
    let second = try await service.sync(instance: instance, credential: demoCredential, in: context)
    #expect(second.count == 2)
    #expect(try context.fetch(FetchDescriptor<CachedShift>()).count == 2)
}

@Test @MainActor func newsSyncServiceInsertsAndUpdatesWithoutDuplicating() async throws {
    let context = try makeInMemoryContext()
    let instance = Instance(name: "Demo", baseURL: Instance.demoBaseURL, apiKeyKeychainRef: "ref")
    context.insert(instance)

    let service = NewsSyncService()
    _ = try await service.sync(instance: instance, credential: demoCredential, in: context)
    _ = try await service.sync(instance: instance, credential: demoCredential, in: context)

    #expect(try context.fetch(FetchDescriptor<CachedNews>()).count == 2)
}

@Test @MainActor func profileSyncServiceInsertsAndUpdatesWithoutDuplicating() async throws {
    let context = try makeInMemoryContext()
    let instance = Instance(name: "Demo", baseURL: Instance.demoBaseURL, apiKeyKeychainRef: "ref")
    context.insert(instance)

    let service = ProfileSyncService()
    let profile = try await service.syncProfile(instance: instance, credential: demoCredential, in: context)
    #expect(profile.name == "demo")

    _ = try await service.syncProfile(instance: instance, credential: demoCredential, in: context)
    #expect(try context.fetch(FetchDescriptor<CachedUser>()).count == 1)

    let worklogs = try await service.syncWorklogs(instance: instance, credential: demoCredential, in: context)
    #expect(worklogs.count == 1)
    _ = try await service.syncWorklogs(instance: instance, credential: demoCredential, in: context)
    #expect(try context.fetch(FetchDescriptor<CachedWorklog>()).count == 1)

    let angelTypes = try await service.syncAngelTypes(instance: instance, credential: demoCredential, in: context)
    #expect(angelTypes.count == 1)
    #expect(angelTypes.first?.angelTypeName == "Engel")
    _ = try await service.syncAngelTypes(instance: instance, credential: demoCredential, in: context)
    #expect(try context.fetch(FetchDescriptor<CachedAngelTypeMembership>()).count == 1)
}

@Test func instanceCredentialResolverThrowsWhenNoKeyIsStored() {
    let instance = Instance(name: "Untouched", baseURL: "https://engelsystem.example.org", apiKeyKeychainRef: UUID().uuidString)
    #expect(throws: InstanceCredentialError.apiKeyNotFound) {
        _ = try InstanceCredentialResolver().credential(for: instance)
    }
}

// `ModelContainerFactory` splits `Instance` (CloudKit-backed) from the `Cached*` models
// (local-only) into separate `ModelConfiguration`s — see Instance.swift for why (SwiftData
// relationships can't cross configurations, unlike before this split). This exercises that
// container end-to-end: inserting and fetching both an `Instance` and a `CachedShift`
// through the same `ModelContext`, which only works if the split configurations are wired
// up correctly. Runs against whichever path `ICloudAvailability.isAvailable` takes in this
// environment (almost always the local-only fallback in a `swift test` CLI process, since
// there's no signed app / entitlements context) — either way, both model types must work.
@Test @MainActor func modelContainerFactorySupportsBothInstanceAndLocalModels() throws {
    let container = ModelContainerFactory.makeContainer(
        localSchemaTypes: [CachedShift.self],
        isStoredInMemoryOnly: true,
        forceLocalOnly: true
    )
    let context = ModelContext(container)

    let instance = Instance(name: "Demo", baseURL: Instance.demoBaseURL, apiKeyKeychainRef: "ref")
    context.insert(instance)
    try context.save()
    #expect(try context.fetch(FetchDescriptor<Instance>()).count == 1)

    let shift = CachedShift(
        serverID: 1,
        instanceID: instance.id,
        title: "Test Shift",
        startsAt: Date(),
        endsAt: Date().addingTimeInterval(3600),
        locationID: 1,
        shiftTypeID: 1,
        url: "https://example.org/shifts/1"
    )
    context.insert(shift)
    try context.save()
    #expect(try context.fetch(FetchDescriptor<CachedShift>()).count == 1)
}
