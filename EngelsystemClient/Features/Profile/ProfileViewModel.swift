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

    func refresh(instance: Instance, in modelContext: ModelContext) async {
        errorMessage = nil
        isUnauthorized = false
        isLoading = true
        defer { isLoading = false }
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
            print("[ProfileViewModel] refresh failed: \(error)")
            guard !SyncErrorMapper.isCancellation(error) else { return }
            errorMessage = SyncErrorMapper.message(for: error)
            isUnauthorized = SyncErrorMapper.isUnauthorized(error)
        }
    }
}
