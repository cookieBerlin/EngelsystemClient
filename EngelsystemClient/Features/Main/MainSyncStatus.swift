import Foundation
import EngelsystemClientKit

/// Drives `SyncProgressBanner` while `MainView`'s app-start sync runs (2026-09-22,
/// user-requested): the sync itself is nonblocking (an async `.task`, never freezes
/// the UI), but with no visible indicator it *looked* frozen — nothing on screen
/// suggested anything was happening. This is deliberately its own tiny observable
/// object rather than reusing one of the per-screen ViewModels: the app-start sync
/// runs via the headless `AppSyncCoordinator`, not any single screen's ViewModel, and
/// showing its progress shouldn't require constructing a ShiftsViewModel/NewsViewModel/
/// ProfileViewModel early just to hang a progress bar off of.
@Observable
@MainActor
final class MainSyncStatus {
    var isSyncing = false
    var completed = 0
    var total = 0
    var statusText = ""
    var didFail = false

    /// The app-start sync runs only when the per-device toggle is on; both it and the main
    /// page's pull-to-refresh need at least one active instance to sync.
    nonisolated static func shouldRunStartSync(syncOnAppStartEnabled: Bool, activeInstanceCount: Int) -> Bool {
        syncOnAppStartEnabled && activeInstanceCount > 0
    }

    var fraction: Double {
        total > 0 ? Double(completed) / Double(total) : 0
    }

    func begin() {
        isSyncing = true
        completed = 0
        total = 0
        statusText = "Syncing…"
        didFail = false
    }

    func apply(_ progress: AppSyncCoordinator.Progress) {
        completed = progress.completed
        total = progress.total
        statusText = progress.description
    }

    func finish(succeeded: Bool) {
        didFail = !succeeded
        statusText = succeeded ? "Updated" : "Partially failed"
    }

    /// Keeps the banner visible for a brief moment after `finish(succeeded:)` so the
    /// success/failure state is actually seen, then hides it — shared by every
    /// caller below instead of each repeating the same sleep-then-hide dance.
    private func showBrieflyThenHide() async {
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        isSyncing = false
    }

    /// Runs `work`, showing an indeterminate banner (no step count — just
    /// `statusText`) for its duration. Used by pull-to-refresh on Shifts/News/Profile
    /// (2026-09-22, user-requested — "the banner should show for every pull-to-refresh,
    /// not just the app-start sync"): those only ever sync their own single domain via
    /// their own ViewModel, so there's no multi-step `AppSyncCoordinator.Progress` to
    /// report — just "is it running" and "did it succeed".
    func run(statusText: String, _ work: () async -> Bool) async {
        isSyncing = true
        completed = 0
        total = 0
        self.statusText = statusText
        didFail = false

        let succeeded = await work()
        finish(succeeded: succeeded)
        await showBrieflyThenHide()
    }

    /// Same as `run(statusText:_:)`, but for a caller that *does* have per-step
    /// progress to report — `AppSyncCoordinator.syncEverything`'s `onProgress`, used
    /// by both `MainView`'s app-start sync and its own pull-to-refresh.
    func runCoordinated(_ work: (@escaping (AppSyncCoordinator.Progress) -> Void) async -> Bool) async {
        begin()
        let succeeded = await work { self.apply($0) }
        finish(succeeded: succeeded)
        await showBrieflyThenHide()
    }
}
