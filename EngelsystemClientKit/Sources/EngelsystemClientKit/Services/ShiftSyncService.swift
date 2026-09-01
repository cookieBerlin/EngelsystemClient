import Foundation
import SwiftData

/// Fetches the current user's shifts for an instance and upserts them into
/// `CachedShift`. Takes an already-resolved `EventCredential` rather than an
/// `Instance` + keychain lookup, so it stays free of Keychain side effects and
/// easy to unit test (see `InstanceCredentialResolver` for resolving one).
@MainActor
public struct ShiftSyncService {
    private let apiClient: APIClient

    public init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    @discardableResult
    public func sync(instance: Instance, credential: EventCredential, in modelContext: ModelContext) async throws -> [CachedShift] {
        let shifts = try await apiClient.fetchShifts(for: .me, credential)
        return try upsert(shifts, instanceID: instance.id, instance: instance, in: modelContext)
    }

    @discardableResult
    private func upsert(_ shifts: [Shift], instanceID: UUID, instance: Instance, in modelContext: ModelContext) throws -> [CachedShift] {
        var result: [CachedShift] = []
        for shift in shifts {
            let uid = CachedShift.uid(instanceID: instanceID, serverID: shift.id)
            var descriptor = FetchDescriptor<CachedShift>(predicate: #Predicate { $0.uid == uid })
            descriptor.fetchLimit = 1

            if let existing = try modelContext.fetch(descriptor).first {
                existing.apply(shift)
                existing.instance = instance
                result.append(existing)
            } else {
                let cached = CachedShift(shift: shift, instanceID: instanceID)
                cached.instance = instance
                modelContext.insert(cached)
                result.append(cached)
            }
        }
        return result
    }
}
