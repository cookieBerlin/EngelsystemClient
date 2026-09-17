import Foundation
import SwiftData
import EngelsystemClientKit

@Observable
@MainActor
final class ProfileViewModel {
    var isLoading = false
    var errorMessage: String?
    var isUnauthorized = false

    private let syncService: ProfileSyncService
    private let credentialResolver: InstanceCredentialResolver

    // `ProfileSyncService` is @MainActor, so its default can't be evaluated as a
    // parameter default (those are evaluated in a nonisolated context) — it has
    // to be constructed inside this (already MainActor-isolated) init body instead.
    init(syncService: ProfileSyncService? = nil, credentialResolver: InstanceCredentialResolver? = nil) {
        self.syncService = syncService ?? ProfileSyncService()
        self.credentialResolver = credentialResolver ?? InstanceCredentialResolver()
    }

    /// Syncs every currently active instance's profile/worklogs/angel types (2026-09-17
    /// multi-active-instance redesign, CLAUDE.md) — a failure on one instance doesn't
    /// prevent the others from refreshing.
    func refresh(instances: [Instance], in modelContext: ModelContext) async {
        errorMessage = nil
        isUnauthorized = false
        isLoading = true
        defer { isLoading = false }

        var lastError: Error?

        for instance in instances {
            do {
                let credential = try credentialResolver.credential(for: instance)
                print("[ProfileViewModel] instance.userID = \(String(describing: instance.userID)), userReference = \(instance.userReference)")
                let profile = try await syncService.syncProfile(instance: instance, credential: credential, in: modelContext)
                print("[ProfileViewModel] synced profile '\(profile.name)' from \(credential.baseURL)")
                let worklogs = try await syncService.syncWorklogs(instance: instance, credential: credential, in: modelContext)
                print("[ProfileViewModel] synced \(worklogs.count) worklog(s)")
                let angelTypes = try await syncService.syncAngelTypes(instance: instance, credential: credential, in: modelContext)
                print("[ProfileViewModel] synced \(angelTypes.count) angel type membership(s)")
            } catch {
                print("[ProfileViewModel] refresh failed for '\(instance.name)': \(error)")
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
