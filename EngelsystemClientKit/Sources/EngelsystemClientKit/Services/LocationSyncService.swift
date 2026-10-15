import Foundation
import SwiftData

/// Fetches an instance's locations and upserts them into `CachedLocation`. See
/// `ShiftSyncService` for why this takes an already-resolved `EventCredential` rather
/// than an `Instance` + keychain lookup.
@MainActor
public struct LocationSyncService {
    private let apiClient: APIClient
    private let capabilities: ServerCapabilities

    public init(apiClient: APIClient = .shared, capabilities: ServerCapabilities? = nil) {
        self.apiClient = apiClient
        self.capabilities = capabilities ?? .shared
    }

    @discardableResult
    public func sync(instance: Instance, credential: EventCredential, in modelContext: ModelContext) async throws -> [CachedLocation] {
        let locations: [Location]
        do {
            locations = try await apiClient.fetchLocations(credential)
        } catch APIError.forbidden {
            // COMPAT(#1711): without that PR only the `api` group may read locations — not an
            // error for the app, the Locations area is simply hidden for this instance.
            capabilities.record(.locationsList, afterFailure: .forbidden, for: instance.id)
            return []
        }
        capabilities.record(.locationsList, state: .available, evidence: .probe, for: instance.id)
        return try upsert(locations, instanceID: instance.id, in: modelContext)
    }

    private func upsert(_ locations: [Location], instanceID: UUID, in modelContext: ModelContext) throws -> [CachedLocation] {
        var result: [CachedLocation] = []
        for location in locations {
            let uid = CachedLocation.uid(instanceID: instanceID, serverID: location.id)
            var descriptor = FetchDescriptor<CachedLocation>(predicate: #Predicate { $0.uid == uid })
            descriptor.fetchLimit = 1

            if let existing = try modelContext.fetch(descriptor).first {
                existing.apply(location)
                result.append(existing)
            } else {
                let cached = CachedLocation(location: location, instanceID: instanceID)
                modelContext.insert(cached)
                result.append(cached)
            }
        }
        return result
    }

    /// Live-refreshes a single location (`APIClient.fetchLocation(id:_:)`) and upserts
    /// just that one row — backs `LocationDetailView`'s own pull-to-refresh (2026-09-23),
    /// separate from the full-list `sync(instance:credential:in:)` above. Inserts if the
    /// row somehow doesn't already exist (defensive — in practice a detail view is only
    /// ever reached from an already-cached row), same upsert shape as the list sync.
    @discardableResult
    public func refreshOne(serverID: Int, instance: Instance, credential: EventCredential, in modelContext: ModelContext) async throws -> CachedLocation {
        let location: Location
        do {
            location = try await apiClient.fetchLocation(id: serverID, credential)
        } catch let error as APIError where error == .notFound || error == .forbidden {
            // COMPAT(#1711): servers without `GET /locations/{id}` answer 404/403.
            capabilities.record(.locationDetail, afterFailure: error, for: instance.id)
            throw error
        }
        capabilities.record(.locationDetail, state: .available, evidence: .probe, for: instance.id)
        let uid = CachedLocation.uid(instanceID: instance.id, serverID: location.id)
        var descriptor = FetchDescriptor<CachedLocation>(predicate: #Predicate { $0.uid == uid })
        descriptor.fetchLimit = 1

        if let existing = try modelContext.fetch(descriptor).first {
            existing.apply(location)
            return existing
        } else {
            let cached = CachedLocation(location: location, instanceID: instance.id)
            modelContext.insert(cached)
            return cached
        }
    }
}
