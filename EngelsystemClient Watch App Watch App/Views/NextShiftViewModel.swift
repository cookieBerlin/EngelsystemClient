import Foundation
import SwiftData
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
                await notificationScheduler.syncNotifications(for: shifts)
            }
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
