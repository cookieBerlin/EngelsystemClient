import Foundation
import SwiftData

/// The result of a `ShiftSyncService.sync` call — `shifts` is every synced shift
/// (matching `sync`'s previous plain-array return shape), `didChange` is whether this
/// sync actually inserted a new shift or modified an existing one (added 2026-09-23,
/// for the "notify the Watch when shifts change" feature — see `AppSyncCoordinator`).
/// Mirrors `NewsSyncResult`'s shape/reasoning.
public struct ShiftSyncResult {
    public let shifts: [CachedShift]
    public let didChange: Bool
}

/// Fetches the current user's shifts for an instance and upserts them into
/// `CachedShift`. Takes an already-resolved `EventCredential` rather than an
/// `Instance` + keychain lookup, so it stays free of Keychain side effects and
/// easy to unit test (see `InstanceCredentialResolver` for resolving one).
@MainActor
public struct ShiftSyncService {
    private let apiClient: APIClient
    private let capabilities: ServerCapabilities

    public init(apiClient: APIClient = .shared, capabilities: ServerCapabilities? = nil) {
        self.apiClient = apiClient
        self.capabilities = capabilities ?? .shared
    }

    @discardableResult
    public func sync(instance: Instance, credential: EventCredential, in modelContext: ModelContext) async throws -> ShiftSyncResult {
        let shifts = try await apiClient.fetchShifts(credential)
        for (feature, supported) in ServerCapabilities.shiftFeaturesSupported(by: shifts) {
            capabilities.record(feature, state: supported ? .available : .notOffered, evidence: .field, for: instance.id)
        }
        return try upsert(shifts, instanceID: instance.id, in: modelContext)
    }

    /// Refreshes one shift via `GET /shifts/{id}` and updates its cached row in place.
    /// COMPAT(#1724): 404/403 are recorded as "not offered"/"not allowed" and rethrown for the caller
    /// to keep the cached shift without an error.
    @discardableResult
    public func refreshOne(serverID: Int, instance: Instance, credential: EventCredential, in modelContext: ModelContext) async throws -> CachedShift {
        let shift: Shift
        do {
            shift = try await apiClient.fetchShift(id: serverID, credential)
        } catch let error as APIError where error == .notFound || error == .forbidden {
            capabilities.record(.singleShiftRefresh, afterFailure: error, for: instance.id)
            throw error
        }
        capabilities.record(.singleShiftRefresh, state: .available, evidence: .probe, for: instance.id)
        return try upsert([shift], instanceID: instance.id, in: modelContext).shifts[0]
    }

    private func upsert(_ shifts: [Shift], instanceID: UUID, in modelContext: ModelContext) throws -> ShiftSyncResult {
        var result: [CachedShift] = []
        var didChange = false
        for shift in shifts {
            let uid = CachedShift.uid(instanceID: instanceID, serverID: shift.id)
            var descriptor = FetchDescriptor<CachedShift>(predicate: #Predicate { $0.uid == uid })
            descriptor.fetchLimit = 1

            if let existing = try modelContext.fetch(descriptor).first {
                if existing.apply(shift) {
                    didChange = true
                }
                result.append(existing)
            } else {
                let cached = CachedShift(shift: shift, instanceID: instanceID)
                modelContext.insert(cached)
                result.append(cached)
                didChange = true
            }
        }
        return ShiftSyncResult(shifts: result, didChange: didChange)
    }
}
