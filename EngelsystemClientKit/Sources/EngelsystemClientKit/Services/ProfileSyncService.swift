import Foundation
import SwiftData

/// Fetches the current user's own profile and worklogs for an instance and
/// upserts them into `CachedUser`/`CachedWorklog`. See `ShiftSyncService` for
/// why this takes an already-resolved `EventCredential`.
@MainActor
public struct ProfileSyncService {
    private let apiClient: APIClient
    private let capabilities: ServerCapabilities

    public init(apiClient: APIClient = .shared, capabilities: ServerCapabilities? = nil) {
        self.apiClient = apiClient
        self.capabilities = capabilities ?? .shared
    }

    @discardableResult
    public func syncProfile(instance: Instance, credential: EventCredential, in modelContext: ModelContext) async throws -> CachedUser {
        let profile = try await apiClient.fetchOwnProfile(credential)
        // COMPAT(#1709): servers with the access concept tell which privileges the account has.
        capabilities.applyPrivileges(profile.privileges, for: instance.id)
        return try upsertProfile(profile, instanceID: instance.id, in: modelContext)
    }

    @discardableResult
    public func syncWorklogs(instance: Instance, credential: EventCredential, in modelContext: ModelContext) async throws -> [CachedWorklog] {
        let worklogs = try await apiClient.fetchWorklogs(credential)
        return try upsertWorklogs(worklogs, instanceID: instance.id, in: modelContext)
    }

    @discardableResult
    public func syncAngelTypes(instance: Instance, credential: EventCredential, in modelContext: ModelContext) async throws -> [CachedAngelTypeMembership] {
        let memberships = try await apiClient.fetchOwnAngelTypes(credential)
        return try upsertAngelTypes(memberships, instanceID: instance.id, in: modelContext)
    }

    private func upsertProfile(_ profile: UsersIdGet200ResponseData, instanceID: UUID, in modelContext: ModelContext) throws -> CachedUser {
        let uid = CachedUser.uid(instanceID: instanceID, serverID: profile.id)
        var descriptor = FetchDescriptor<CachedUser>(predicate: #Predicate { $0.uid == uid })
        descriptor.fetchLimit = 1

        if let existing = try modelContext.fetch(descriptor).first {
            existing.apply(profile)
            return existing
        } else {
            let cached = CachedUser(profile: profile, instanceID: instanceID)
            modelContext.insert(cached)
            return cached
        }
    }

    @discardableResult
    private func upsertWorklogs(_ worklogs: [Worklog], instanceID: UUID, in modelContext: ModelContext) throws -> [CachedWorklog] {
        var result: [CachedWorklog] = []
        for worklog in worklogs {
            let uid = CachedWorklog.uid(instanceID: instanceID, serverID: worklog.id)
            var descriptor = FetchDescriptor<CachedWorklog>(predicate: #Predicate { $0.uid == uid })
            descriptor.fetchLimit = 1

            if let existing = try modelContext.fetch(descriptor).first {
                existing.apply(worklog)
                result.append(existing)
            } else {
                let cached = CachedWorklog(worklog: worklog, instanceID: instanceID)
                modelContext.insert(cached)
                result.append(cached)
            }
        }
        return result
    }

    @discardableResult
    private func upsertAngelTypes(_ memberships: [UserAngelType], instanceID: UUID, in modelContext: ModelContext) throws -> [CachedAngelTypeMembership] {
        var result: [CachedAngelTypeMembership] = []
        for membership in memberships {
            let uid = CachedAngelTypeMembership.uid(instanceID: instanceID, serverID: membership.angeltype.id)
            var descriptor = FetchDescriptor<CachedAngelTypeMembership>(predicate: #Predicate { $0.uid == uid })
            descriptor.fetchLimit = 1

            if let existing = try modelContext.fetch(descriptor).first {
                existing.apply(membership)
                result.append(existing)
            } else {
                let cached = CachedAngelTypeMembership(membership: membership, instanceID: instanceID)
                modelContext.insert(cached)
                result.append(cached)
            }
        }
        return result
    }
}
