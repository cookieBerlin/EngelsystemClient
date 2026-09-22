import Foundation
import BackgroundTasks
import SwiftData
import EngelsystemClientKit

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

    /// Registers the task handler — must happen before the app finishes launching
    /// (Apple's documented requirement), so this is called from
    /// `EngelsystemClientApp.init`, not from `.task`/`.onAppear`.
    static func register(modelContainer: ModelContainer) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            handle(refreshTask, modelContainer: modelContainer)
        }
    }

    private static func handle(_ task: BGAppRefreshTask, modelContainer: ModelContainer) {
        let context = ModelContext(modelContainer)
        let syncTask = Task {
            let instances = ((try? context.fetch(FetchDescriptor<Instance>())) ?? []).filter(\.isActive)
            let succeeded = await AppSyncCoordinator().syncEverything(
                instances: instances,
                in: context,
                notifyOnNewNews: true
            )
            DeviceSyncPreferences.recordBackgroundSync()
            scheduleNext()
            task.setTaskCompleted(success: succeeded)
        }

        // The OS gives a background task a strict time budget; if it's about to be
        // exceeded, cancel the in-flight sync and let it wind down via its own
        // cooperative cancellation checks rather than being killed mid-write.
        task.expirationHandler = {
            syncTask.cancel()
        }
    }

    /// Submits the next `BGAppRefreshTaskRequest`, or cancels any pending one if the
    /// configured interval is `.manual`. Call after every background run (above) and
    /// whenever the interval setting changes (`SettingsView`) — the interval is a
    /// plain per-device preference (`DeviceSyncPreferences`, not CloudKit-synced; see
    /// its doc comment for why), so there's no cross-device "the other device changed
    /// it" case to guard against here any more, unlike an earlier version of this
    /// feature.
    static func scheduleNext() {
        let interval = DeviceSyncPreferences.pollingInterval()
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        guard let seconds = interval.timeInterval else { return }

        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: seconds)
        try? BGTaskScheduler.shared.submit(request)
    }
}
