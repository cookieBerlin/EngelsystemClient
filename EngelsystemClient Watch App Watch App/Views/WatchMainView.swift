import SwiftUI
import SwiftData
import EngelsystemClientKit

/// Root view once at least one instance is configured. 2026-09-17 multi-active-instance
/// redesign (CLAUDE.md): any number of instances can be active at once
/// (`Instance.isActive`), so this no longer resolves a single active instance —
/// `NextShiftView` receives every active instance and shows the nearest upcoming shift
/// across all of them (still exactly one shift, per the Watch's minimal scope).
///
/// 2026-09-22, user-requested background-sync feature: `NextShiftView` no longer syncs
/// on its own appearance (see its doc comment) — this view now owns the one-shot
/// app-start sync instead, via the same headless `AppSyncCoordinator` the iOS
/// `MainView` uses (Shifts only here, per the Watch's minimal scope — no News/Profile
/// catalog to sync). No progress-bar UI like iOS's `SyncProgressBanner`: the watch
/// screen is too small for it, so `NextShiftView` just gets a one-line "Syncing…" flag
/// instead — the shift *data* still updates reactively via `@Query` either way.
struct WatchMainView: View {
    let instances: [Instance]

    @Environment(\.modelContext) private var modelContext
    @State private var isAppStartSyncing = false

    private var activeInstances: [Instance] { instances.filter(\.isActive) }

    var body: some View {
        NextShiftView(instances: activeInstances, isAppStartSyncing: isAppStartSyncing)
            .task {
                guard DeviceSyncPreferences.syncOnAppStartEnabled() else { return }
                guard !activeInstances.isEmpty else { return }
                isAppStartSyncing = true
                _ = await AppSyncCoordinator().syncEverything(instances: activeInstances, in: modelContext, shiftsOnly: true)
                isAppStartSyncing = false
            }
    }
}
