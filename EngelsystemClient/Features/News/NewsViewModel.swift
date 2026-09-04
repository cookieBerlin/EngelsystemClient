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

    func refresh(instance: Instance, in modelContext: ModelContext) async {
        errorMessage = nil
        isUnauthorized = false
        isLoading = true
        defer { isLoading = false }
        do {
            let credential = try credentialResolver.credential(for: instance)
            let news = try await syncService.sync(instance: instance, credential: credential, in: modelContext)
            print("[NewsViewModel] synced \(news.count) news item(s) from \(credential.baseURL)")
        } catch {
            print("[NewsViewModel] refresh failed: \(error)")
            guard !SyncErrorMapper.isCancellation(error) else { return }
            errorMessage = SyncErrorMapper.message(for: error)
            isUnauthorized = SyncErrorMapper.isUnauthorized(error)
        }
    }
}
