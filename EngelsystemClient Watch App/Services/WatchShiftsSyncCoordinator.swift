import Foundation
import SwiftData
import EngelsystemClientKit

/// Single entry point for "resync shifts now" on the Watch — 2026-09-23, "keep the Watch
/// fresh" feature. Used by every trigger that can fire independently of the others:
/// `WatchMainView`'s app-start sync, the CloudKit `Instance.shiftsChangedAt` remote-change
/// signal (`RemoteChangeRefresh`), and the WatchConnectivity nudge
/// (`WatchConnectivityReceiver`). Coalesces overlapping triggers into a single in-flight
/// sync — if two of these fire close together for the same underlying change (expected,
/// since both the CloudKit signal and the WatchConnectivity nudge are triggered by the
/// same iOS-side event), the later one is simply dropped rather than racing a second
/// concurrent sync; the baseline app-start sync and the user's own pull-to-refresh still
/// guarantee eventual consistency either way.
///
/// Always updates the complication after a successful sync (`WatchComplicationUpdater`) —
/// this is what actually fixes the pre-existing "app-start sync never touched the
/// complication" gap, since `WatchMainView` now goes through this coordinator instead of
/// calling `AppSyncCoordinator` directly.
@MainActor
final class WatchShiftsSyncCoordinator {
    static let shared = WatchShiftsSyncCoordinator()

    private let appSyncCoordinator: AppSyncCoordinator
    private let snapshotStore: NextShiftSnapshotStore
    private var isRefreshing = false

    // `AppSyncCoordinator` is @MainActor, so its default can't be evaluated as a
    // parameter default (those are evaluated in a nonisolated context) — same reason
    // ShiftsViewModel/NextShiftViewModel construct their @MainActor defaults inside the
    // (already MainActor-isolated) init body instead. Both parameters are
    // test-injectable so `WatchShiftsSyncCoordinatorTests` can pass an `AppSyncCoordinator`
    // built with a fake `NotificationScheduler`/`NewsNotifier` (avoiding the real
    // `UNUserNotificationCenter`) and a `NextShiftSnapshotStore` pointed at a unique test
    // suite name (avoiding writes to the real shared App Group during tests).
    init(appSyncCoordinator: AppSyncCoordinator? = nil, snapshotStore: NextShiftSnapshotStore = NextShiftSnapshotStore()) {
        self.appSyncCoordinator = appSyncCoordinator ?? AppSyncCoordinator()
        self.snapshotStore = snapshotStore
    }

    /// For callers outside any View's body (the CloudKit-change handler, the
    /// WatchConnectivity delegate) that have no `@Query`-backed instance list of their
    /// own to pass in — fetches every active `Instance` directly from `modelContext`.
    func refreshActiveInstances(in modelContext: ModelContext, handleNotifications: Bool = true) async {
        let instances = ((try? modelContext.fetch(FetchDescriptor<Instance>())) ?? []).filter(\.isActive)
        await refresh(instances: instances, in: modelContext, handleNotifications: handleNotifications)
    }

    /// `handleNotifications` mirrors `AppSyncCoordinator.syncEverything`'s own parameter
    /// of the same name/purpose — always `true` in production, only ever `false` from
    /// tests that inject a fake notification center (see that parameter's doc comment on
    /// `AppSyncCoordinator` for why no fake can honestly stand in for
    /// `UNUserNotificationCenter.notificationSettings()`).
    func refresh(instances: [Instance], in modelContext: ModelContext, handleNotifications: Bool = true) async {
        guard !instances.isEmpty else { return }
        guard !isRefreshing else {
            DebugLog.log("WatchShiftsSyncCoordinator: refresh already in flight — skipping")
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        DebugLog.log("WatchShiftsSyncCoordinator: refreshing \(instances.count) instance(s)")
        _ = await appSyncCoordinator.syncEverything(
            instances: instances,
            in: modelContext,
            shiftsOnly: true,
            handleNotifications: handleNotifications
        )

        let instanceIDs = Set(instances.map(\.id))
        let allShifts = ((try? modelContext.fetch(FetchDescriptor<CachedShift>())) ?? [])
            .filter { instanceIDs.contains($0.instanceID) }
        WatchComplicationUpdater.refresh(shifts: allShifts, store: snapshotStore)
        DebugLog.log("WatchShiftsSyncCoordinator: refresh finished, complication updated")
    }
}
