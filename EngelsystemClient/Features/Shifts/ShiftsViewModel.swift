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
    func refresh(instances: [Instance], in modelContext: ModelContext) async {
        errorMessage = nil
        isUnauthorized = false
        isLoading = true
        defer { isLoading = false }

        var allShifts: [CachedShift] = []
        var lastError: Error?

        for instance in instances {
            do {
                let credential = try credentialResolver.credential(for: instance)
                print("[ShiftsViewModel] instance.userID = \(String(describing: instance.userID)), userReference = \(instance.userReference)")
                let shifts = try await syncService.sync(instance: instance, credential: credential, in: modelContext)
                print("[ShiftsViewModel] synced \(shifts.count) shift(s) from \(credential.baseURL)")
                allShifts.append(contentsOf: shifts)
            } catch {
                print("[ShiftsViewModel] refresh failed for '\(instance.name)': \(error)")
                guard !SyncErrorMapper.isCancellation(error) else { continue }
                lastError = error
            }
        }

        if let lastError {
            errorMessage = SyncErrorMapper.message(for: lastError)
            isUnauthorized = SyncErrorMapper.isUnauthorized(lastError)
        } else if await notificationScheduler.requestAuthorizationIfNeeded() {
            let minutesBefore = NotificationScheduler.configuredMinutesBefore()
            await notificationScheduler.syncNotifications(for: allShifts, minutesBefore: minutesBefore)
        }
    }
}
