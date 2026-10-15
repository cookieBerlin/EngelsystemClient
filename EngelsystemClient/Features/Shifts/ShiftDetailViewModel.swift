import Foundation
import SwiftData
import EngelsystemClientKit

/// Refreshes one shift from the server (`GET /shifts/{id}`) and updates the cached row in place;
/// the page observes the same `CachedShift`. COMPAT(#1724): servers without the endpoint answer
/// 404/403 — the page then just keeps showing the cached shift, without an error.
@Observable
@MainActor
final class ShiftDetailViewModel {
    var isLoading = false
    var errorMessage: String?
    var refreshUnavailable = false

    private let syncService: ShiftSyncService
    private let credentialResolver: InstanceCredentialResolver

    init(syncService: ShiftSyncService? = nil, credentialResolver: InstanceCredentialResolver? = nil) {
        self.syncService = syncService ?? ShiftSyncService()
        self.credentialResolver = credentialResolver ?? InstanceCredentialResolver()
    }

    func refresh(shift: CachedShift, instance: Instance, in modelContext: ModelContext) async {
        errorMessage = nil
        refreshUnavailable = false
        isLoading = true
        defer { isLoading = false }

        do {
            let credential = try credentialResolver.credential(for: instance)
            _ = try await syncService.refreshOne(serverID: shift.serverID, instance: instance, credential: credential, in: modelContext)
            DebugLog.log("[ShiftDetailViewModel] refreshed shift \(shift.serverID)")
        } catch {
            if error is CancellationError { return }
            if let apiError = error as? APIError, [APIError.notFound, .forbidden].contains(apiError) {
                DebugLog.log("[ShiftDetailViewModel] server has no single-shift endpoint (\(apiError)) — keeping the cached shift", level: .warning)
                refreshUnavailable = true
                return
            }
            DebugLog.log("[ShiftDetailViewModel] refresh failed: \(error)", level: .error)
            errorMessage = SyncErrorMapper.message(for: error)
        }
    }
}
