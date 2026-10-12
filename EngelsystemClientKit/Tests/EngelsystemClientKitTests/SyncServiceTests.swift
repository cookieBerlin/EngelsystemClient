import Foundation
import SwiftData
import UserNotifications
import Testing
@testable import EngelsystemClientKit

/// Accepts and records everything, authorized by default — the coordinator talks to this
/// instead of the real notification center (which crashes under `swift test`).
final class RecordingNotificationCenter: NotificationCenterScheduling, @unchecked Sendable {
    var status: UNAuthorizationStatus = .authorized
    var added: [UNNotificationRequest] = []
    func authorizationStatus() async -> UNAuthorizationStatus { status }
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { status == .authorized }
    func pendingNotificationRequests() async -> [UNNotificationRequest] { added }
    func add(_ request: UNNotificationRequest) async throws { added.append(request) }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        added.removeAll { identifiers.contains($0.identifier) }
    }
}

@MainActor
private func makeTestCoordinator() -> AppSyncCoordinator {
    AppSyncCoordinator(
        notificationScheduler: NotificationScheduler(center: RecordingNotificationCenter()),
        newsNotifier: NewsNotifier(center: RecordingNotificationCenter())
    )
}

@MainActor
private func makeInMemoryContext() throws -> ModelContext {
    let schema = Schema([
        Instance.self, NotificationLeadTimeSettings.self, CachedShift.self, CachedNews.self, CachedUser.self,
        CachedWorklog.self, CachedAngelTypeMembership.self, CachedLocation.self,
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
    #expect(first.shifts.count == DemoData.shifts.count)
    #expect(first.didChange) // fresh inserts always count as a change
    #expect(try context.fetch(FetchDescriptor<CachedShift>()).count == DemoData.shifts.count)

    // Syncing again must update the existing rows in place, not duplicate them.
    let second = try await service.sync(instance: instance, credential: demoCredential, in: context)
    #expect(second.shifts.count == DemoData.shifts.count)
    #expect(try context.fetch(FetchDescriptor<CachedShift>()).count == DemoData.shifts.count)
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
    #expect(first.items.count == DemoData.news.count)
    #expect(first.insertedItems.count == DemoData.news.count)

    // Syncing again must update the existing rows in place (reporting them as
    // already-known, not newly inserted), not duplicate them.
    let second = try await service.sync(instance: instance, credential: demoCredential, in: context)
    #expect(second.items.count == DemoData.news.count)
    #expect(second.insertedItems.isEmpty)
    #expect(try context.fetch(FetchDescriptor<CachedNews>()).count == DemoData.news.count)
}

@Test @MainActor func locationSyncServiceInsertsAndUpdatesWithoutDuplicating() async throws {
    let context = try makeInMemoryContext()
    let instance = Instance(name: "Demo", baseURL: Instance.demoBaseURL, apiKeyKeychainRef: "ref")
    context.insert(instance)

    let service = LocationSyncService()
    let first = try await service.sync(instance: instance, credential: demoCredential, in: context)
    #expect(first.count == DemoData.locations.count)
    #expect(try context.fetch(FetchDescriptor<CachedLocation>()).count == DemoData.locations.count)

    // Syncing again must update the existing rows in place, not duplicate them.
    let second = try await service.sync(instance: instance, credential: demoCredential, in: context)
    #expect(second.count == DemoData.locations.count)
    #expect(try context.fetch(FetchDescriptor<CachedLocation>()).count == DemoData.locations.count)
}

/// 2026-09-23, "keep the Watch fresh"-adjacent feature (Locations): `refreshOne` backs
/// `LocationDetailView`'s own pull-to-refresh via the newly added `GET /locations/{id}`
/// — separate from the full-list `sync` above, and must update the *same* cached row
/// (not create a duplicate) when one already exists.
@Test @MainActor func locationSyncServiceRefreshOneUpdatesTheExistingCachedRow() async throws {
    let context = try makeInMemoryContext()
    let instance = Instance(name: "Demo", baseURL: Instance.demoBaseURL, apiKeyKeychainRef: "ref")
    context.insert(instance)

    let service = LocationSyncService()
    _ = try await service.sync(instance: instance, credential: demoCredential, in: context)
    #expect(try context.fetch(FetchDescriptor<CachedLocation>()).count == DemoData.locations.count)

    let refreshed = try await service.refreshOne(serverID: 1, instance: instance, credential: demoCredential, in: context)
    #expect(refreshed.name == "Heaven")
    #expect(try context.fetch(FetchDescriptor<CachedLocation>()).count == DemoData.locations.count) // still no duplicate
}

@Test func apiClientFetchLocationReturnsDemoDataAndThrowsNotFoundForUnknownID() async throws {
    let client = APIClient.shared
    let location = try await client.fetchLocation(id: 1, demoCredential)
    #expect(location.name == "Heaven")

    await #expect(throws: APIError.notFound) {
        _ = try await client.fetchLocation(id: 999, demoCredential)
    }
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
        onProgress: { progressUpdates.append($0) }
    )

    #expect(succeeded)
    #expect(progressUpdates.count == 5) // Shifts + News + Profile + Locations + Messages, one active instance
    #expect(progressUpdates.last?.completed == 5)
    #expect(progressUpdates.last?.total == 5)
    #expect(try context.fetch(FetchDescriptor<CachedShift>()).count == DemoData.shifts.count)
    #expect(try context.fetch(FetchDescriptor<CachedNews>()).count == DemoData.news.count)
    #expect(try context.fetch(FetchDescriptor<CachedUser>()).count == 1)
    #expect(try context.fetch(FetchDescriptor<CachedLocation>()).count == DemoData.locations.count)
    #expect(instance.messagesSupported)
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
        shiftsOnly: true
    )

    #expect(instance.shiftsChangedAt > Date.distantPast)
}

@Test @MainActor func appSyncCoordinatorShiftsOnlySkipsNewsProfileAndLocations() async throws {
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
        onProgress: { progressUpdates.append($0) }
    )

    #expect(progressUpdates.count == 1)
    #expect(try context.fetch(FetchDescriptor<CachedShift>()).count == DemoData.shifts.count)
    #expect(try context.fetch(FetchDescriptor<CachedNews>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<CachedLocation>()).isEmpty)
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
        onProgress: { progressUpdates.append($0) }
    )

    #expect(!succeeded)
    #expect(progressUpdates.count == 5) // still reports every planned step
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
    #expect(worklogs.count == DemoData.worklogs.count)
    _ = try await service.syncWorklogs(instance: instance, credential: demoCredential, in: context)
    #expect(try context.fetch(FetchDescriptor<CachedWorklog>()).count == DemoData.worklogs.count)

    let angelTypes = try await service.syncAngelTypes(instance: instance, credential: demoCredential, in: context)
    #expect(angelTypes.count == DemoData.ownAngelTypes.count)
    #expect(angelTypes.first?.angelTypeName == "Engel")
    _ = try await service.syncAngelTypes(instance: instance, credential: demoCredential, in: context)
    #expect(try context.fetch(FetchDescriptor<CachedAngelTypeMembership>()).count == DemoData.ownAngelTypes.count)
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
