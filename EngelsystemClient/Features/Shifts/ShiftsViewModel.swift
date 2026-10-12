import Foundation
import SwiftData
import EngelsystemClientKit

@Observable
@MainActor
final class ShiftsViewModel {
    var isLoading = false
    var errorMessage: String?
    var isUnauthorized = false

    private let syncService: ShiftSyncService
    private let credentialResolver: InstanceCredentialResolver
    private let notificationScheduler: NotificationScheduler

    // `ShiftSyncService` is @MainActor, so its default can't be evaluated as a
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

    /// Syncs every currently active instance (2026-09-17 multi-active-instance redesign,
    /// CLAUDE.md — any number of instances can be active at once) and aggregates their
    /// shifts. Notifications are only (re)synced when every instance in `instances`
    /// synced cleanly this pass — if one fails, previously scheduled notifications for
    /// the others are deliberately left untouched rather than risk the combined
    /// "cancel whatever's no longer in the synced set" logic dropping a still-valid
    /// notification for an instance that simply didn't get a chance to re-sync.
    /// `handleNotifications` mirrors `AppSyncCoordinator.syncEverything`'s own parameter
    /// of the same name/purpose (2026-09-23, added for testability) — always `true` in
    /// production; only ever `false` from tests, since `requestAuthorizationIfNeeded()`
    /// calls the real `UNUserNotificationCenter.notificationSettings()`, which returns
    /// `UNNotificationSettings`, a type with no public initializer at all, so no fake can
    /// honestly stand in for it (same documented boundary as `AppSyncCoordinator`'s).
    func refresh(instances: [Instance], in modelContext: ModelContext, handleNotifications: Bool = true) async {
        errorMessage = nil
        isUnauthorized = false
        isLoading = true
        defer { isLoading = false }

        var allShifts: [CachedShift] = []
        var lastError: Error?

        for instance in instances {
            do {
                let credential = try credentialResolver.credential(for: instance)
                let result = try await syncService.sync(instance: instance, credential: credential, in: modelContext)
                DebugLog.log("[ShiftsViewModel] synced \(result.shifts.count) shift(s) from \(credential.baseURL)")
                allShifts.append(contentsOf: result.shifts)
                // 2026-09-23, "keep the Watch fresh" feature — this pull-to-refresh path
                // bypasses AppSyncCoordinator, so it needs the same signal-bump here too.
                if result.didChange {
                    instance.shiftsChangedAt = Date()
                    instance.touch()
                    try? modelContext.save()
                    WatchConnectivityBridge.notifyShiftsChanged()
                }
            } catch {
                DebugLog.log("[ShiftsViewModel] refresh failed for '\(instance.name)': \(error)", level: .error)
                guard !SyncErrorMapper.isCancellation(error) else { continue }
                lastError = error
            }
        }

        if let lastError {
            errorMessage = SyncErrorMapper.message(for: lastError)
            isUnauthorized = SyncErrorMapper.isUnauthorized(lastError)
        } else if handleNotifications, await notificationScheduler.requestAuthorizationIfNeeded() {
            let leadTimes = NotificationLeadTimeSettings.resolve(in: modelContext).leadTimesMinutes
            await notificationScheduler.syncNotifications(for: allShifts, leadTimes: leadTimes)
        }
    }
}
