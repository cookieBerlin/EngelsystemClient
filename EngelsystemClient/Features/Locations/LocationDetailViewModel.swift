import Foundation
import SwiftData
import EngelsystemClientKit

/// Live-refreshes a single location (`GET /locations/{id}`, added 2026-09-23) and
/// updates the already-cached `CachedLocation` row in place — unlike
/// `NewsDetailViewModel`'s comments, a location *is* already cached (via the list sync,
/// `LocationSyncService.sync`), so there's no separate published state to hold here:
/// `LocationDetailView` observes the same `CachedLocation` instance directly, and
/// SwiftData's own model observation picks up the mutation `refreshOne` makes.
///
/// This endpoint is on a server branch not yet merged upstream (PR
/// engelsystem/engelsystem#1711) — a server without it just surfaces a normal error
/// here; the rest of the Locations feature (the cached list, the link from a shift)
/// never depends on it.
@Observable
@MainActor
final class LocationDetailViewModel {
    var isLoading = false
    var errorMessage: String?

    private let syncService: LocationSyncService
    private let credentialResolver: InstanceCredentialResolver

    init(syncService: LocationSyncService? = nil, credentialResolver: InstanceCredentialResolver? = nil) {
        self.syncService = syncService ?? LocationSyncService()
        self.credentialResolver = credentialResolver ?? InstanceCredentialResolver()
    }

    func refresh(location: CachedLocation, instance: Instance, in modelContext: ModelContext) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let credential = try credentialResolver.credential(for: instance)
            _ = try await syncService.refreshOne(serverID: location.serverID, instance: instance, credential: credential, in: modelContext)
            DebugLog.log("[LocationDetailViewModel] refreshed location \(location.serverID)")
        } catch {
            // Same guard every other sync entry point in this app applies — a SwiftUI
            // `.task`/`.refreshable` cancelled because the view disappeared isn't a
            // real failure and shouldn't show an error banner.
            if error is CancellationError { return }
            DebugLog.log("[LocationDetailViewModel] refresh failed: \(error)", level: .error)
            errorMessage = SyncErrorMapper.message(for: error)
        }
    }
}
