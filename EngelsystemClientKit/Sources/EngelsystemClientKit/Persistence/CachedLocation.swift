import Foundation
import SwiftData

@Model
public final class CachedLocation {
    // Composite unique key prevents collision across instances with the same server-assigned ID
    @Attribute(.unique) public var uid: String
    public var serverID: Int
    public var instanceID: UUID

    public var name: String
    public var locationDescription: String
    public var mapUrl: String?
    // Flattened from the API's `contact: {dect}` object — this project's only contact
    // method today (see `ContactDect`); kept as a plain optional rather than a nested
    // struct, matching how `CachedShift` already flattens its own nested References.
    public var contactDect: String?
    public var url: String
    public var cachedAt: Date

    // No relationship to Instance — it lives in a separate, CloudKit-backed
    // ModelConfiguration; see Instance.swift. Callers filter by `instanceID` instead.

    public init(
        serverID: Int,
        instanceID: UUID,
        name: String,
        locationDescription: String,
        mapUrl: String? = nil,
        contactDect: String? = nil,
        url: String
    ) {
        self.uid = "\(instanceID.uuidString):\(serverID)"
        self.serverID = serverID
        self.instanceID = instanceID
        self.name = name
        self.locationDescription = locationDescription
        self.mapUrl = mapUrl
        self.contactDect = contactDect
        self.url = url
        self.cachedAt = Date()
    }
}

// MARK: - Mapping from the generated `Location` DTO

public extension CachedLocation {
    convenience init(location: Location, instanceID: UUID) {
        self.init(
            serverID: location.id,
            instanceID: instanceID,
            name: location.name,
            locationDescription: location.description,
            mapUrl: location.mapUrl,
            contactDect: location.contact.dect,
            url: location.url
        )
    }

    /// Updates all fields from a freshly fetched `Location` DTO (used by
    /// `LocationSyncService` when a cached row already exists for this location).
    func apply(_ location: Location) {
        name = location.name
        locationDescription = location.description
        mapUrl = location.mapUrl
        contactDect = location.contact.dect
        url = location.url
        updateCacheTimestamp()
    }

    static func uid(instanceID: UUID, serverID: Int) -> String {
        "\(instanceID.uuidString):\(serverID)"
    }

    func updateCacheTimestamp() { cachedAt = Date() }
}

// MARK: - Sorting

public extension CachedLocation {
    static func sortedByName(_ locations: [CachedLocation]) -> [CachedLocation] {
        locations.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
