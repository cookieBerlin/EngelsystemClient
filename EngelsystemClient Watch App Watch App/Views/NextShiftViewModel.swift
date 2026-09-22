import Foundation
import SwiftData
import WidgetKit
import EngelsystemClientKit

@Observable
@MainActor
final class NextShiftViewModel {
    var isLoading = false
    var errorMessage: String?
    var lastUpdated: Date?

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
    func refresh(instances: [Instance], in modelContext: ModelContext) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        var allShifts: [CachedShift] = []
        var lastError: Error?

        for instance in instances {
            do {
                let credential = try credentialResolver.credential(for: instance)
                print("[NextShiftViewModel] instance.userID = \(String(describing: instance.userID)), userReference = \(instance.userReference)")
                let shifts = try await syncService.sync(instance: instance, credential: credential, in: modelContext)
                print("[NextShiftViewModel] synced \(shifts.count) shift(s) from \(credential.baseURL)")
                allShifts.append(contentsOf: shifts)
            } catch {
                print("[NextShiftViewModel] refresh failed for '\(instance.name)': \(error)")
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

        lastUpdated = Date()
        if await notificationScheduler.requestAuthorizationIfNeeded() {
            let leadTimes = NotificationLeadTimeSettings.resolve(in: modelContext).leadTimesMinutes
            await notificationScheduler.syncNotifications(for: allShifts, leadTimes: leadTimes)
        }

        // Publish to the App Group so the complication (a separate process with no
        // Keychain access of its own) has something to read — see NextShiftSnapshotStore.
        let nextShift = CachedShift.nextShift(from: allShifts)
        NextShiftSnapshotStore().save(
            nextShift.map {
                NextShiftSnapshot(title: $0.title, startsAt: $0.startsAt, endsAt: $0.endsAt, locationName: $0.locationName)
            }
        )
        WidgetCenter.shared.reloadAllTimelines()
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
