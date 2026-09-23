import Foundation
import SwiftData
import EngelsystemClientKit

@Observable
@MainActor
final class NextShiftViewModel {
    var isLoading = false
    var errorMessage: String?

    private let syncService: ShiftSyncService
    private let credentialResolver: InstanceCredentialResolver
    private let notificationScheduler: NotificationScheduler

    // ShiftSyncService is @MainActor, so its default can't be evaluated as a
    // parameter default (those are evaluated in a nonisolated context) — it has
    // to be constructed inside this (already MainActor-isolated) init body instead.
    init(
        syncService: ShiftSyncService? = nil,
        credentialResolver: InstanceCredentialResolver? = nil,
        notificationScheduler: NotificationScheduler = NotificationScheduler()
    ) {
        self.syncService = syncService ?? ShiftSyncService()
        self.credentialResolver = credentialResolver ?? InstanceCredentialResolver()
        self.notificationScheduler = notificationScheduler
    }

    /// Local notification scheduling on the Watch too, for the next shift (CLAUDE.md
    /// Watch App Scope) — reuses the same `NotificationScheduler` as the iOS app.
    /// Still shows exactly one shift (per the Watch's deliberately minimal scope), but
    /// since the 2026-09-17 multi-active-instance redesign it's the chronologically
    /// nearest upcoming shift across *every* active instance, not a single pre-selected
    /// one — each active instance is synced in turn and the results combined before
    /// picking the next shift and updating the complication snapshot.
    /// `handleNotifications` mirrors `AppSyncCoordinator.syncEverything`'s own parameter
    /// of the same name/purpose (2026-09-23, added for testability) — always `true` in
    /// production; only ever `false` from tests, since `requestAuthorizationIfNeeded()`
    /// calls the real `UNUserNotificationCenter.notificationSettings()`, which returns
    /// `UNNotificationSettings`, a type with no public initializer at all, so no fake can
    /// honestly stand in for it (same documented boundary as `AppSyncCoordinator`'s).
    func refresh(instances: [Instance], in modelContext: ModelContext, handleNotifications: Bool = true) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        var allShifts: [CachedShift] = []
        var lastError: Error?

        for instance in instances {
            do {
                let credential = try credentialResolver.credential(for: instance)
                DebugLog.log("[NextShiftViewModel] instance.userID = \(String(describing: instance.userID)), userReference = \(instance.userReference)")
                let result = try await syncService.sync(instance: instance, credential: credential, in: modelContext)
                DebugLog.log("[NextShiftViewModel] synced \(result.shifts.count) shift(s) from \(credential.baseURL)")
                allShifts.append(contentsOf: result.shifts)
                // 2026-09-23, "keep the Watch fresh" feature: this pull-to-refresh path
                // doesn't go through AppSyncCoordinator, so it needs the same signal-bump
                // here too — harmless even though only iOS's WatchConnectivityBridge side
                // actually sends anything; keeps the CloudKit signal symmetric so a change
                // the Watch notices first (e.g. it happened to sync before the iPhone did)
                // still reaches the iPhone eventually.
                if result.didChange {
                    instance.shiftsChangedAt = Date()
                    instance.touch()
                    try? modelContext.save()
                    WatchConnectivityBridge.notifyShiftsChanged()
                }
            } catch {
                DebugLog.log("[NextShiftViewModel] refresh failed for '\(instance.name)': \(error)", level: .error)
                // Cancellation (e.g. a `.task` cancelled because the view disappeared)
                // isn't a real failure — don't show it as a "Connection failed" error.
                guard !(error is CancellationError) else { continue }
                lastError = error
            }
        }

        if let lastError {
            errorMessage = Self.message(for: lastError)
            return
        }

        if handleNotifications, await notificationScheduler.requestAuthorizationIfNeeded() {
            let leadTimes = NotificationLeadTimeSettings.resolve(in: modelContext).leadTimesMinutes
            await notificationScheduler.syncNotifications(for: allShifts, leadTimes: leadTimes)
        }

        // Publish to the App Group so the complication (a separate process with no
        // Keychain access of its own) has something to read — see
        // WatchComplicationUpdater (2026-09-23: factored out so every sync trigger,
        // not just this manual pull-to-refresh, keeps the complication current).
        WatchComplicationUpdater.refresh(shifts: allShifts)
    }

    private static func message(for error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.userMessage
        }
        if error is InstanceCredentialError {
            return "No API key found. Set up the Watch app again."
        }
        return error.localizedDescription
    }
}
