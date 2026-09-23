import Foundation
import SwiftData
import UserNotifications
import Testing
@testable import EngelsystemClientKit

/// Never actually invoked in these tests (`AppSyncCoordinator` is always called with
/// `handleNotifications: false` here) — exists only so `AppSyncCoordinator`'s init
/// doesn't fall back to its literal `NotificationScheduler()` default, which would
/// construct the real `UNUserNotificationCenter.current()` and crash immediately
/// under `swift test`'s CLI harness (no host app bundle). See the doc comment on
/// `AppSyncCoordinator.syncEverything`'s `handleNotifications` parameter.
private final class UnusedNotificationCenter: NotificationCenterScheduling, @unchecked Sendable {
    func notificationSettings() async -> UNNotificationSettings { fatalError("not used with handleNotifications: false") }
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { fatalError("not used with handleNotifications: false") }
    func pendingNotificationRequests() async -> [UNNotificationRequest] { fatalError("not used with handleNotifications: false") }
    func add(_ request: UNNotificationRequest) async throws { fatalError("not used with handleNotifications: false") }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) { fatalError("not used with handleNotifications: false") }
}

@MainActor
private func makeTestCoordinator() -> AppSyncCoordinator {
    AppSyncCoordinator(
        notificationScheduler: NotificationScheduler(center: UnusedNotificationCenter()),
        newsNotifier: NewsNotifier(center: UnusedNotificationCenter())
    )
}

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
    #expect(first.shifts.count == 2)
    #expect(first.didChange) // fresh inserts always count as a change
    #expect(try context.fetch(FetchDescriptor<CachedShift>()).count == 2)

    // Syncing again must update the existing rows in place, not duplicate them.
    let second = try await service.sync(instance: instance, credential: demoCredential, in: context)
    #expect(second.shifts.count == 2)
    #expect(try context.fetch(FetchDescriptor<CachedShift>()).count == 2)
}

/// `CachedShift.apply(_:)` is the pure diffing logic `ShiftSyncResult.didChange` relies
/// on (2026-09-23, "keep the Watch fresh" feature) — tested directly here rather than
/// through `ShiftSyncService`/`DemoData`, since `DemoData.shifts` recomputes `startsAt`/
/// `endsAt` relative to `Date()` on every call, which would make two consecutive real
/// syncs *always* look "changed" and defeat a "no real change" test at that level.
@Test @MainActor func cachedShiftApplyReportsWhetherAnythingActuallyChanged() {
    let location = Reference(id: 1, name: "Heaven")
    let shiftType = Reference(id: 2, name: "Info Desk")
    let start = Date()
    let end = start.addingTimeInterval(3600)
    let dto = Shift(
        id: 1, name: "Info Desk Shift", description: "Help visitors",
        startsAt: start, endsAt: end, location: location, shiftType: shiftType,
        scheduleGuid: nil, createdAt: nil, updatedAt: nil, neededAngelTypes: [],
        url: "https://example.org/shifts/1"
    )
    let cached = CachedShift(shift: dto, instanceID: UUID())

    // Applying the exact same data again must report no change.
    #expect(cached.apply(dto) == false)

    // A real change to a single field must be detected.
    let movedDTO = Shift(
        id: 1, name: dto.name, description: dto.description,
        startsAt: start.addingTimeInterval(600), endsAt: end, location: location, shiftType: shiftType,
        scheduleGuid: nil, createdAt: nil, updatedAt: nil, neededAngelTypes: [],
        url: dto.url
    )
    #expect(cached.apply(movedDTO) == true)

    // And applying that same (now-current) data again must go back to no change.
    #expect(cached.apply(movedDTO) == false)
}

@Test @MainActor func newsSyncServiceInsertsAndUpdatesWithoutDuplicating() async throws {
    let context = try makeInMemoryContext()
    let instance = Instance(name: "Demo", baseURL: Instance.demoBaseURL, apiKeyKeychainRef: "ref")
    context.insert(instance)

    let service = NewsSyncService()
    let first = try await service.sync(instance: instance, credential: demoCredential, in: context)
    #expect(first.items.count == 2)
    #expect(first.insertedItems.count == 2)

    // Syncing again must update the existing rows in place (reporting them as
    // already-known, not newly inserted), not duplicate them.
    let second = try await service.sync(instance: instance, credential: demoCredential, in: context)
    #expect(second.items.count == 2)
    #expect(second.insertedItems.isEmpty)
    #expect(try context.fetch(FetchDescriptor<CachedNews>()).count == 2)
}

/// `AppSyncCoordinator` resolves its own credential internally (unlike the other
/// tests in this file, which pass `demoCredential` straight into a sync service) —
/// needs a real Keychain entry under the instance's `apiKeyKeychainRef`, same as
/// `InstanceSetupServiceTests` already does elsewhere in this suite. Cleans the entry
/// up afterward so repeat runs stay deterministic.
@Test @MainActor func appSyncCoordinatorSyncsShiftsNewsAndProfileAndReportsProgress() async throws {
    let context = try makeInMemoryContext()
    let ref = "app-sync-coordinator-test-\(UUID().uuidString)"
    let store = LocalKeychainStore()
    try store.save(apiKey: "demo", for: ref)
    defer { try? store.deleteAPIKey(for: ref) }

    let instance = Instance(name: "Demo", baseURL: Instance.demoBaseURL, apiKeyKeychainRef: ref)
    context.insert(instance)

    var progressUpdates: [AppSyncCoordinator.Progress] = []
    let succeeded = await makeTestCoordinator().syncEverything(
        instances: [instance],
        in: context,
        handleNotifications: false,
        onProgress: { progressUpdates.append($0) }
    )

    #expect(succeeded)
    #expect(progressUpdates.count == 3) // Shifts + News + Profile, one active instance
    #expect(progressUpdates.last?.completed == 3)
    #expect(progressUpdates.last?.total == 3)
    #expect(try context.fetch(FetchDescriptor<CachedShift>()).count == 2)
    #expect(try context.fetch(FetchDescriptor<CachedNews>()).count == 2)
    #expect(try context.fetch(FetchDescriptor<CachedUser>()).count == 1)
}

/// 2026-09-23, "keep the Watch fresh" feature: `AppSyncCoordinator` must bump
/// `Instance.shiftsChangedAt` away from its `.distantPast` default whenever a sync
/// actually inserts/changes a shift — this is the CloudKit-synced signal
/// `refreshesOnRemoteCloudKitChange` reacts to on the Watch, and what
/// `WatchConnectivityBridge.notifyShiftsChanged()` (a safe no-op under `swift test`,
/// since `WatchConnectivity` isn't `canImport`-able on macOS) is meant to accompany.
@Test @MainActor func appSyncCoordinatorBumpsShiftsChangedAtOnARealChange() async throws {
    let context = try makeInMemoryContext()
    let ref = "app-sync-coordinator-test-\(UUID().uuidString)"
    let store = LocalKeychainStore()
    try store.save(apiKey: "demo", for: ref)
    defer { try? store.deleteAPIKey(for: ref) }

    let instance = Instance(name: "Demo", baseURL: Instance.demoBaseURL, apiKeyKeychainRef: ref)
    #expect(instance.shiftsChangedAt == Date.distantPast)
    context.insert(instance)

    _ = await makeTestCoordinator().syncEverything(
        instances: [instance],
        in: context,
        shiftsOnly: true,
        handleNotifications: false
    )

    #expect(instance.shiftsChangedAt > Date.distantPast)
}

@Test @MainActor func appSyncCoordinatorShiftsOnlySkipsNewsAndProfile() async throws {
    let context = try makeInMemoryContext()
    let ref = "app-sync-coordinator-test-\(UUID().uuidString)"
    let store = LocalKeychainStore()
    try store.save(apiKey: "demo", for: ref)
    defer { try? store.deleteAPIKey(for: ref) }

    let instance = Instance(name: "Demo", baseURL: Instance.demoBaseURL, apiKeyKeychainRef: ref)
    context.insert(instance)

    var progressUpdates: [AppSyncCoordinator.Progress] = []
    _ = await makeTestCoordinator().syncEverything(
        instances: [instance],
        in: context,
        shiftsOnly: true,
        handleNotifications: false,
        onProgress: { progressUpdates.append($0) }
    )

    #expect(progressUpdates.count == 1)
    #expect(try context.fetch(FetchDescriptor<CachedShift>()).count == 2)
    #expect(try context.fetch(FetchDescriptor<CachedNews>()).isEmpty)
}

@Test @MainActor func appSyncCoordinatorFailsGracefullyWhenNoCredentialIsStored() async throws {
    let context = try makeInMemoryContext()
    // No Keychain entry saved for this ref at all.
    let instance = Instance(name: "Demo", baseURL: Instance.demoBaseURL, apiKeyKeychainRef: "missing-\(UUID().uuidString)")
    context.insert(instance)

    var progressUpdates: [AppSyncCoordinator.Progress] = []
    let succeeded = await makeTestCoordinator().syncEverything(
        instances: [instance],
        in: context,
        handleNotifications: false,
        onProgress: { progressUpdates.append($0) }
    )

    #expect(!succeeded)
    #expect(progressUpdates.count == 3) // still reports every planned step
    #expect(try context.fetch(FetchDescriptor<CachedShift>()).isEmpty)
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
