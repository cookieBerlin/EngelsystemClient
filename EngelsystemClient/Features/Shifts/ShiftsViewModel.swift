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

    func refresh(instance: Instance, in modelContext: ModelContext) async {
        errorMessage = nil
        isUnauthorized = false
        isLoading = true
        defer { isLoading = false }
        do {
            let credential = try credentialResolver.credential(for: instance)
            let shifts = try await syncService.sync(instance: instance, credential: credential, in: modelContext)
            if await notificationScheduler.requestAuthorizationIfNeeded() {
                let minutesBefore = NotificationScheduler.configuredMinutesBefore()
                await notificationScheduler.syncNotifications(for: shifts, minutesBefore: minutesBefore)
            }
        } catch {
            errorMessage = SyncErrorMapper.message(for: error)
            isUnauthorized = SyncErrorMapper.isUnauthorized(error)
        }
    }
}
