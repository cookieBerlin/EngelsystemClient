import Foundation
import WidgetKit
import EngelsystemClientKit

/// Writes the next-shift snapshot to the shared App Group and reloads the complication's
/// timelines. Factored out of `NextShiftViewModel.refresh` (2026-09-23, "keep the Watch
/// fresh" feature) so every trigger that can update shifts — manual pull-to-refresh, the
/// app-start sync, the CloudKit `Instance.shiftsChangedAt` signal, and the WatchConnectivity
/// nudge — keeps the complication in sync too, not just whichever one happened to call
/// this directly before. Fixes a pre-existing gap: the app-start sync (`WatchMainView`)
/// used to sync `CachedShift` via `AppSyncCoordinator` directly and never touched the
/// complication at all; only a manual pull-to-refresh did.
enum WatchComplicationUpdater {
    /// `store` is injectable purely for `WatchComplicationUpdaterTests` — defaults to the
    /// real shared App Group store in production, matching `NextShiftSnapshotStoreTests`'
    /// own pattern of pointing a test at a unique, non-shared suite name instead of the
    /// real App Group.
    static func refresh(shifts: [CachedShift], store: NextShiftSnapshotStore = NextShiftSnapshotStore()) {
        let nextShift = CachedShift.nextShift(from: shifts)
        store.save(
            nextShift.map {
                NextShiftSnapshot(title: $0.title, startsAt: $0.startsAt, endsAt: $0.endsAt, locationName: $0.locationName)
            }
        )
        WidgetCenter.shared.reloadAllTimelines()
    }
}
