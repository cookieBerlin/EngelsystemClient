import Foundation
import SwiftData
import EngelsystemClientKit

@Observable
@MainActor
final class NewsViewModel {
    var isLoading = false
    var errorMessage: String?
    var isUnauthorized = false

    private let syncService: NewsSyncService
    private let credentialResolver: InstanceCredentialResolver

    // `NewsSyncService` is @MainActor, so its default can't be evaluated as a
    // parameter default (those are evaluated in a nonisolated context) — it has
    // to be constructed inside this (already MainActor-isolated) init body instead.
    init(syncService: NewsSyncService? = nil, credentialResolver: InstanceCredentialResolver? = nil) {
        self.syncService = syncService ?? NewsSyncService()
        self.credentialResolver = credentialResolver ?? InstanceCredentialResolver()
    }

    /// Syncs every currently active instance (2026-09-17 multi-active-instance redesign,
    /// CLAUDE.md) — each instance's news is upserted independently, so a failure on one
    /// doesn't prevent the others from refreshing.
    ///
    /// This is only ever reached via pull-to-refresh now (2026-09-22 background-sync
    /// feature — see CLAUDE.md): the screen-open `.task` that used to trigger this too
    /// is gone. Deliberately does **not** post a "new news" notification here, unlike
    /// `AppSyncCoordinator.syncEverything` — the user is already looking at this screen
    /// when they pull to refresh it, so a push notification about content they're about
    /// to see anyway would just be noise. `NewsSyncService.sync`'s `insertedItems` are
    /// still available if that ever needs to change, just unused here on purpose.
    func refresh(instances: [Instance], in modelContext: ModelContext) async {
        errorMessage = nil
        isUnauthorized = false
        isLoading = true
        defer { isLoading = false }

        var lastError: Error?

        for instance in instances {
            do {
                let credential = try credentialResolver.credential(for: instance)
                let result = try await syncService.sync(instance: instance, credential: credential, in: modelContext)
                DebugLog.log("[NewsViewModel] synced \(result.items.count) news item(s) from \(credential.baseURL)")
            } catch {
                DebugLog.log("[NewsViewModel] refresh failed for '\(instance.name)': \(error)", level: .error)
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
