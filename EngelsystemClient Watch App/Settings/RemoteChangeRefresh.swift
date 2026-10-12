import SwiftUI
import SwiftData
import CoreData
import Combine
import EngelsystemClientKit

/// Watch equivalent of the iOS app's `RemoteChangeRefresh` (`Features/Shared`) —
/// duplicated rather than shared since it's SwiftUI view-layer code, and this project
/// keeps UI-layer code out of the platform-agnostic `EngelsystemClientKit` package.
extension View {
    /// `.receive(on: DispatchQueue.main)` is required: Core Data posts
    /// `NSPersistentStoreRemoteChange` from a background queue, and `ModelContext` is
    /// main-actor-bound — see the iOS counterpart's doc comment for the full story.
    ///
    /// 2026-09-23, "keep the Watch fresh" feature: beyond the `modelContext.save()`
    /// this already did (needed so `@Query` actually notices the merge at all), also
    /// triggers a shifts resync via `WatchShiftsSyncCoordinator` — a CloudKit merge here
    /// could mean `Instance.shiftsChangedAt` just changed, so opportunistically resyncing
    /// shifts on *any* remote change is simpler and cheap enough than trying to inspect
    /// which field actually changed. Only reacts while this View (and therefore the
    /// app process) is alive — reliably waking from a fully suspended/terminated Watch
    /// app via this notification alone is unverified; the WatchConnectivity nudge and
    /// the Watch's own periodic/app-start sync are what cover that gap (see
    /// `docs/architecture.md`).
    func refreshesOnRemoteCloudKitChange(modelContext: ModelContext) -> some View {
        onReceive(
            NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)
                .receive(on: DispatchQueue.main)
        ) { _ in
            try? modelContext.save()
            DebugLog.log("RemoteChangeRefresh (Watch): CloudKit remote change observed — resyncing shifts")
            Task { await WatchShiftsSyncCoordinator.shared.refreshActiveInstances(in: modelContext) }
        }
    }
}
