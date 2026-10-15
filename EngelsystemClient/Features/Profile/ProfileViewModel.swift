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
    private let capabilities: ServerCapabilities

    // `ProfileSyncService` is @MainActor, so its default can't be evaluated as a
    // parameter default (those are evaluated in a nonisolated context) — it has
    // to be constructed inside this (already MainActor-isolated) init body instead.
    init(syncService: ProfileSyncService? = nil, credentialResolver: InstanceCredentialResolver? = nil,
         capabilities: ServerCapabilities? = nil) {
        self.capabilities = capabilities ?? .shared
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
                let profile = try await syncService.syncProfile(instance: instance, credential: credential, in: modelContext)
                DebugLog.log("[ProfileViewModel] synced profile '\(profile.name)' from \(credential.baseURL)")
                // Work logs and angel types are optional parts of the profile: a 403/404 hides just that
                // part silently (Features list, ADR 0015).
                do {
                    let worklogs = try await syncService.syncWorklogs(instance: instance, credential: credential, in: modelContext)
                    DebugLog.log("[ProfileViewModel] synced \(worklogs.count) worklog(s)")
                    capabilities.record(.profileWorklogs, state: .available, evidence: .probe, for: instance.id)
                } catch {
                    if !capabilities.record(.profileWorklogs, afterError: error, for: instance.id) { throw error }
                }
                do {
                    let angelTypes = try await syncService.syncAngelTypes(instance: instance, credential: credential, in: modelContext)
                    DebugLog.log("[ProfileViewModel] synced \(angelTypes.count) angel type membership(s)")
                    capabilities.record(.profileAngelTypes, state: .available, evidence: .probe, for: instance.id)
                } catch {
                    if !capabilities.record(.profileAngelTypes, afterError: error, for: instance.id) { throw error }
                }
            } catch {
                DebugLog.log("[ProfileViewModel] refresh failed for '\(instance.name)': \(error)", level: .error)
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
