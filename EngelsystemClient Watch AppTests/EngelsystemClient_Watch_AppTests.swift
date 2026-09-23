//
//  EngelsystemClient_Watch_AppTests.swift
//  EngelsystemClient Watch AppTests
//
//  Created by Angelo Cuccato on 31.08.26.
//

import Foundation
import Testing
import SwiftData
import UserNotifications
import EngelsystemClientKit
@testable import EngelsystemClient_Watch_App

/// Never actually invoked (every test below that touches notification scheduling passes
/// `handleNotifications: false`) — exists only so `AppSyncCoordinator`/`NotificationScheduler`
/// don't fall back to the real `UNUserNotificationCenter.current()`, which has no place to
/// run from inside a test. Mirrors `EngelsystemClientKitTests.SyncServiceTests`'
/// `UnusedNotificationCenter`.
private final class UnusedNotificationCenter: NotificationCenterScheduling, @unchecked Sendable {
    func notificationSettings() async -> UNNotificationSettings { fatalError("not used with handleNotifications: false") }
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { fatalError("not used with handleNotifications: false") }
    func pendingNotificationRequests() async -> [UNNotificationRequest] { fatalError("not used with handleNotifications: false") }
    func add(_ request: UNNotificationRequest) async throws { fatalError("not used with handleNotifications: false") }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) { fatalError("not used with handleNotifications: false") }
}

// `cloudKitDatabase: .none` is required here specifically because this test target
// runs hosted inside the real, CloudKit-entitled Watch app (unlike
// `EngelsystemClientKitTests`' bare `swift test` CLI process, which has no
// entitlements context at all and so never attempts real CloudKit schema
// validation) — without it, `Instance`'s CloudKit-required-defaults validation
// actually runs and fails container creation.
@MainActor
private func makeInMemoryContext() throws -> ModelContext {
    let schema = Schema([Instance.self, CachedShift.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try ModelContainer(for: schema, configurations: [config])
    return ModelContext(container)
}

@MainActor
private func makeTestAppSyncCoordinator() -> AppSyncCoordinator {
    AppSyncCoordinator(
        notificationScheduler: NotificationScheduler(center: UnusedNotificationCenter()),
        newsNotifier: NewsNotifier(center: UnusedNotificationCenter())
    )
}

private func uniqueTestSnapshotStore() -> NextShiftSnapshotStore {
    NextShiftSnapshotStore(appGroupID: "net.cuccato.engelsystem.de.tests.\(UUID().uuidString)")
}

/// Seeds a demo `Instance` with a real Keychain entry under a random ref — needed since
/// `AppSyncCoordinator` resolves its own credential internally (unlike `ShiftSyncService`,
/// which the caller resolves a credential for directly). Mirrors
/// `EngelsystemClientKitTests.SyncServiceTests`'s equivalent setup.
@MainActor
private func seedDemoInstance(in context: ModelContext) throws -> Instance {
    let ref = "watch-app-tests-\(UUID().uuidString)"
    try LocalKeychainStore().save(apiKey: "demo", for: ref)
    let instance = Instance(name: "Demo", baseURL: Instance.demoBaseURL, apiKeyKeychainRef: ref)
    context.insert(instance)
    return instance
}

// MARK: - WatchComplicationUpdater

/// 2026-09-23, "keep the Watch fresh" feature — factored out of `NextShiftViewModel
/// .refresh` so every sync trigger (not just a manual pull-to-refresh) keeps the
/// complication current; see `docs/ARCHITECTURE.md`.
struct WatchComplicationUpdaterTests {
    @Test @MainActor func refreshWritesTheNearestUpcomingShiftAsTheSnapshot() {
        let store = uniqueTestSnapshotStore()
        let instanceID = UUID()
        let past = CachedShift(
            serverID: 1, instanceID: instanceID, title: "Past Shift",
            startsAt: Date().addingTimeInterval(-7200), endsAt: Date().addingTimeInterval(-3600),
            locationID: 1, shiftTypeID: 1, url: "https://example.org/1"
        )
        let future = CachedShift(
            serverID: 2, instanceID: instanceID, title: "Next Shift",
            startsAt: Date().addingTimeInterval(3600), endsAt: Date().addingTimeInterval(7200),
            locationID: 2, locationName: "Heaven", shiftTypeID: 1, url: "https://example.org/2"
        )

        WatchComplicationUpdater.refresh(shifts: [past, future], store: store)

        let snapshot = store.load()
        #expect(snapshot?.title == "Next Shift")
        #expect(snapshot?.locationName == "Heaven")
    }

    /// Seeds a stale snapshot first, to prove `refresh` actively clears it rather than
    /// just happening to never have written anything.
    @Test @MainActor func refreshClearsTheSnapshotWhenThereAreNoUpcomingShifts() {
        let store = uniqueTestSnapshotStore()
        store.save(NextShiftSnapshot(title: "Stale", startsAt: Date(), endsAt: Date(), locationName: nil))
        let past = CachedShift(
            serverID: 1, instanceID: UUID(), title: "Past Shift",
            startsAt: Date().addingTimeInterval(-7200), endsAt: Date().addingTimeInterval(-3600),
            locationID: 1, shiftTypeID: 1, url: "https://example.org/1"
        )

        WatchComplicationUpdater.refresh(shifts: [past], store: store)

        #expect(store.load() == nil)
    }
}

// MARK: - WatchShiftsSyncCoordinator

struct WatchShiftsSyncCoordinatorTests {
    @MainActor
    private func makeTestCoordinator() -> WatchShiftsSyncCoordinator {
        WatchShiftsSyncCoordinator(appSyncCoordinator: makeTestAppSyncCoordinator(), snapshotStore: uniqueTestSnapshotStore())
    }

    @Test @MainActor func refreshSyncsShiftsAndUpdatesTheComplicationSnapshot() async throws {
        let context = try makeInMemoryContext()
        let instance = try seedDemoInstance(in: context)
        let coordinator = makeTestCoordinator()

        await coordinator.refresh(instances: [instance], in: context, handleNotifications: false)

        #expect(try context.fetch(FetchDescriptor<CachedShift>()).count == 2)
    }

    @Test @MainActor func refreshDoesNothingWhenInstancesIsEmpty() async throws {
        let context = try makeInMemoryContext()
        let coordinator = makeTestCoordinator()

        await coordinator.refresh(instances: [], in: context, handleNotifications: false)

        #expect(try context.fetch(FetchDescriptor<CachedShift>()).isEmpty)
    }

    /// The re-entrancy guard is what lets the CloudKit signal, the WatchConnectivity
    /// nudge, and the app-start sync fire close together (expected, since the first two
    /// are both triggered by the same iOS-side event) without racing two concurrent
    /// syncs. Exploits `DemoData.simulateLatency()`'s fixed ~300ms delay to distinguish
    /// "did the real sync" (slow) from "short-circuited by the guard" (near-instant).
    @Test @MainActor func refreshCoalescesOverlappingCallsIntoASingleInFlightSync() async throws {
        let context = try makeInMemoryContext()
        let instance = try seedDemoInstance(in: context)
        let coordinator = makeTestCoordinator()

        func timedRefresh() async -> TimeInterval {
            let start = Date()
            await coordinator.refresh(instances: [instance], in: context, handleNotifications: false)
            return Date().timeIntervalSince(start)
        }

        async let firstDuration = timedRefresh()
        try await Task.sleep(nanoseconds: 20_000_000) // let the first call acquire the guard
        let secondDuration = await timedRefresh()

        #expect(await firstDuration > 0.25)
        #expect(secondDuration < 0.1)
    }
}

// MARK: - WatchConnectivityReceiver

struct WatchConnectivityReceiverTests {
    @Test @MainActor func handleApplicationContextTriggersAResync() async throws {
        let schema = Schema([Instance.self, CachedShift.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        _ = try seedDemoInstance(in: container.mainContext)

        let coordinator = WatchShiftsSyncCoordinator(appSyncCoordinator: makeTestAppSyncCoordinator(), snapshotStore: uniqueTestSnapshotStore())
        let receiver = WatchConnectivityReceiver(modelContainer: container, syncCoordinator: coordinator)

        await receiver.handleApplicationContext(handleNotifications: false)

        #expect(try container.mainContext.fetch(FetchDescriptor<CachedShift>()).count == 2)
    }
}

// MARK: - NextShiftViewModel

struct NextShiftViewModelTests {
    /// 2026-09-23, "keep the Watch fresh" feature: this pull-to-refresh path doesn't go
    /// through `AppSyncCoordinator`, so it needs its own signal-bump — see
    /// `EngelsystemClientKitTests.SyncServiceTests
    /// .appSyncCoordinatorBumpsShiftsChangedAtOnARealChange` for the `AppSyncCoordinator`
    /// counterpart of this test.
    @Test @MainActor func refreshBumpsInstanceShiftsChangedAtOnARealChange() async throws {
        let context = try makeInMemoryContext()
        let instance = try seedDemoInstance(in: context)
        #expect(instance.shiftsChangedAt == Date.distantPast)

        let viewModel = NextShiftViewModel(notificationScheduler: NotificationScheduler(center: UnusedNotificationCenter()))
        await viewModel.refresh(instances: [instance], in: context, handleNotifications: false)

        #expect(instance.shiftsChangedAt > Date.distantPast)
    }
}
