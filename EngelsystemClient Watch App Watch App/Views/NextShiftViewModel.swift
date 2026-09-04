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
    func refresh(instance: Instance, in modelContext: ModelContext) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let credential = try credentialResolver.credential(for: instance)
            let shifts = try await syncService.sync(instance: instance, credential: credential, in: modelContext)
            lastUpdated = Date()
            if await notificationScheduler.requestAuthorizationIfNeeded() {
                // No settings UI on the Watch for this (CLAUDE.md "Watch app scope" is
                // deliberately minimal) — always uses the default lead time.
                await notificationScheduler.syncNotifications(
                    for: shifts,
                    minutesBefore: NotificationScheduler.defaultMinutesBefore
                )
            }

            // Publish to the App Group so the complication (a separate process with no
            // Keychain access of its own) has something to read — see NextShiftSnapshotStore.
            let nextShift = CachedShift.nextShift(from: shifts)
            NextShiftSnapshotStore().save(
                nextShift.map {
                    NextShiftSnapshot(title: $0.title, startsAt: $0.startsAt, endsAt: $0.endsAt, locationName: $0.locationName)
                }
            )
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorMessage = Self.message(for: error)
        }
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
