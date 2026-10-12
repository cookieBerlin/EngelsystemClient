import Foundation
import SwiftData
import EngelsystemClientKit

/// The `BackgroundTasks` calls this scheduler needs, behind a protocol so the scheduling
/// and sync logic below is testable — the real `BGTaskScheduler` adapter and the
/// registration/expiry plumbing live in `BackgroundTaskRegistration.swift`.
protocol BackgroundTaskScheduling {
    func cancelRefresh(identifier: String)
    func submitRefresh(identifier: String, earliestBeginDate: Date) throws
}

/// Schedules and runs the interval-based background sync (2026-09-22, user-requested,
/// to reduce server load compared to syncing every time a screen is opened — see
/// CLAUDE.md). **iOS app target only, not `EngelsystemClientKit`**: the
/// `BackgroundTasks` framework isn't available on watchOS at all (confirmed via
/// Apple's own forums/documentation — watchOS has a separate, older
/// `WKApplicationRefreshBackgroundTask` API, which as of watchOS 26 has also been
/// reported unreliable; see CLAUDE.md for the full writeup and why Watch background
/// execution isn't attempted in this feature). The actual sync work
/// (`AppSyncCoordinator`) is still shared Kit code — only this OS-level scheduling
/// layer is platform-specific.
///
/// Uses the classic imperative `BGTaskScheduler.register`/`submit` API rather than the
/// newer SwiftUI `.backgroundTask(.appRefresh(_:))` scene modifier — deliberately: this
/// project can't practically verify a background task's real execution end-to-end (no
/// physical always-on test rig, and the Simulator requires a manual LLDB "simulate
/// launch" command per attempt), so the priority here was picking the API this session
/// could be most confident about the exact shape of, not the newest one.
enum BackgroundSyncScheduler {
    static let taskIdentifier = "net.cuccato.engelsystem.de.backgroundrefresh"

    /// Submits the next refresh request, or cancels any pending one if `interval` is
    /// `.manual`. Called after every background run (below) and whenever the interval
    /// setting changes (`SettingsView`) — the interval is a plain per-device preference
    /// (`DeviceSyncPreferences`, not CloudKit-synced; see its doc comment for why).
    static func scheduleNext(using scheduler: BackgroundTaskScheduling, interval: PollingInterval, now: Date) {
        scheduler.cancelRefresh(identifier: taskIdentifier)
        guard let seconds = interval.timeInterval else {
            DebugLog.log("BackgroundSyncScheduler: not scheduled (interval is Manual)")
            return
        }

        let earliestBeginDate = now.addingTimeInterval(seconds)
        do {
            // 2026-09-23, user-requested: `submit` used to be a silent `try?` — given the
            // well-documented uncertainty around whether this ever actually gets to run at
            // all (see CLAUDE.md), even knowing whether *scheduling itself* succeeded is
            // valuable, previously invisible info.
            try scheduler.submitRefresh(identifier: taskIdentifier, earliestBeginDate: earliestBeginDate)
            DebugLog.log("BackgroundSyncScheduler: scheduled, earliest begin date \(earliestBeginDate)")
        } catch {
            DebugLog.log("BackgroundSyncScheduler: scheduling failed: \(error)", level: .error)
        }
    }

    /// One background sync pass over every active instance, including news announcements
    /// (the one path where those are appropriate — see `NewsNotifier`), then records the
    /// run and schedules the next one. Returns whether everything synced cleanly.
    static func runSync(
        in context: ModelContext,
        coordinator: AppSyncCoordinator,
        scheduler: BackgroundTaskScheduling,
        interval: PollingInterval
    ) async -> Bool {
        // 2026-09-23, user-requested: explicit start/end log entries for the one sync
        // trigger that previously left no trace at all outside of Instruments — there's
        // no UI visible while this runs, so without this the only way to know it ran at
        // all was `DeviceSyncPreferences.lastBackgroundSyncDate()` in Settings.
        DebugLog.log("BackgroundSyncScheduler: background sync started")
        // A failed fetch yields no instances (compactMap drops the nil) — written without `?? []`
        // so there is no never-taken autoclosure region to cover.
        let instances = [try? context.fetch(FetchDescriptor<Instance>())].compactMap { $0 }.flatMap { $0 }.filter(\.isActive)
        let succeeded = await coordinator.syncEverything(instances: instances, in: context, notifyOnNewNews: true)
        DeviceSyncPreferences.recordBackgroundSync()
        scheduleNext(using: scheduler, interval: interval, now: Date())
        DebugLog.log("BackgroundSyncScheduler: background sync finished (succeeded: \(succeeded))", level: succeeded ? .info : .warning)
        return succeeded
    }
}
