import Foundation
import SwiftData
import EngelsystemClientKit

@Observable
@MainActor
final class ShiftsViewModel {
    var isLoading = false
    var errorMessage: String?

    private let syncService: ShiftSyncService
    private let credentialResolver: InstanceCredentialResolver

    // `ShiftSyncService` is @MainActor, so its default can't be evaluated as a
    // parameter default (those are evaluated in a nonisolated context) — it has
    // to be constructed inside this (already MainActor-isolated) init body instead.
    init(syncService: ShiftSyncService? = nil, credentialResolver: InstanceCredentialResolver? = nil) {
        self.syncService = syncService ?? ShiftSyncService()
        self.credentialResolver = credentialResolver ?? InstanceCredentialResolver()
    }

    func refresh(instance: Instance, in modelContext: ModelContext) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let credential = try credentialResolver.credential(for: instance)
            try await syncService.sync(instance: instance, credential: credential, in: modelContext)
        } catch {
            errorMessage = SyncErrorMapper.message(for: error)
        }
    }
}
