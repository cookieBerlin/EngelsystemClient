import Foundation
import SwiftData
import EngelsystemClientKit

@Observable
@MainActor
final class LocationsViewModel {
    var isLoading = false
    var errorMessage: String?
    var isUnauthorized = false

    private let syncService: LocationSyncService
    private let credentialResolver: InstanceCredentialResolver

    // `LocationSyncService` is @MainActor, so its default can't be evaluated as a
    // parameter default (those are evaluated in a nonisolated context) — it has
    // to be constructed inside this (already MainActor-isolated) init body instead.
    init(syncService: LocationSyncService? = nil, credentialResolver: InstanceCredentialResolver? = nil) {
        self.syncService = syncService ?? LocationSyncService()
        self.credentialResolver = credentialResolver ?? InstanceCredentialResolver()
    }

    /// Syncs every currently active instance (2026-09-17 multi-active-instance redesign,
    /// CLAUDE.md) — each instance's locations are upserted independently, so a failure
    /// on one doesn't prevent the others from refreshing. Only ever reached via
    /// pull-to-refresh on this screen — the app-start/background sync already keeps
    /// Locations current via `AppSyncCoordinator` (2026-09-23), same split as
    /// Shifts/News.
    func refresh(instances: [Instance], in modelContext: ModelContext) async {
        errorMessage = nil
        isUnauthorized = false
        isLoading = true
        defer { isLoading = false }

        var lastError: Error?

        for instance in instances {
            do {
                let credential = try credentialResolver.credential(for: instance)
                let locations = try await syncService.sync(instance: instance, credential: credential, in: modelContext)
                DebugLog.log("[LocationsViewModel] synced \(locations.count) location(s) from \(credential.baseURL)")
            } catch {
                DebugLog.log("[LocationsViewModel] refresh failed for '\(instance.name)': \(error)", level: .error)
                guard !SyncErrorMapper.isCancellation(error) else { continue }
                lastError = error
            }
        }

        if let lastError {
            errorMessage = SyncErrorMapper.message(for: lastError)
            isUnauthorized = SyncErrorMapper.isUnauthorized(lastError)
        }
    }
}
