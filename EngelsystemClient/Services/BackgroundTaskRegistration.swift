import Foundation
import BackgroundTasks
import SwiftData
import EngelsystemClientKit

/// Thin adapter over the real `BGTaskScheduler` — kept in its own file because the
/// OS only ever runs these from the system's background-task machinery, which unit
/// tests can't drive. All decisions live in `BackgroundSyncScheduler`, which is tested
/// through `BackgroundTaskScheduling`. Excluded from the coverage gate (standing
/// approval for thin adapters).
struct SystemBackgroundTaskScheduler: BackgroundTaskScheduling {
    func cancelRefresh(identifier: String) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }

    func submitRefresh(identifier: String, earliestBeginDate: Date) throws {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = earliestBeginDate
        try BGTaskScheduler.shared.submit(request)
    }
}

extension BackgroundSyncScheduler {
    /// Registers the task handler — must happen before the app finishes launching
    /// (Apple's documented requirement), so this is called from
    /// `EngelsystemClientApp.init`, not from `.task`/`.onAppear`.
    static func register(modelContainer: ModelContainer) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            handle(refreshTask, modelContainer: modelContainer)
        }
    }

    /// `scheduleNext()` for callers that just want the real scheduler and the current
    /// per-device interval (`SettingsView`).
    static func scheduleNext() {
        scheduleNext(using: SystemBackgroundTaskScheduler(), interval: DeviceSyncPreferences.pollingInterval(), now: Date())
    }

    private static func handle(_ task: BGAppRefreshTask, modelContainer: ModelContainer) {
        let context = ModelContext(modelContainer)
        let syncTask = Task {
            let succeeded = await runSync(
                in: context,
                coordinator: AppSyncCoordinator(),
                scheduler: SystemBackgroundTaskScheduler(),
                interval: DeviceSyncPreferences.pollingInterval()
            )
            task.setTaskCompleted(success: succeeded)
        }

        // The OS gives a background task a strict time budget; if it's about to be
        // exceeded, cancel the in-flight sync and let it wind down via its own
        // cooperative cancellation checks rather than being killed mid-write.
        task.expirationHandler = {
            DebugLog.log("BackgroundSyncScheduler: expired before completion, cancelling", level: .warning)
            syncTask.cancel()
        }
    }
}
