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

// MARK: - Merging across instances

public extension CachedLocation {
    /// One location that survived `mergedAcrossServers`, with the name of every instance whose own cached copy
    /// contributed to it.
    struct MergedItem: Identifiable {
        public let location: CachedLocation
        public let instanceNames: [String]
        public var id: String { location.uid }
    }

    /// Collapses locations that came from different instances pointing at the same server (two accounts of
    /// one Engelsystem): they are the same room. The key is the pair (server base URL, `serverID`); the
    /// first occurrence per key survives, so callers sort first; `instanceNames` collects every instance.
    static func mergedAcrossServers(_ locations: [CachedLocation], instances: [Instance]) -> [MergedItem] {
        let baseURLByInstanceID = Dictionary(uniqueKeysWithValues: instances.map { ($0.id, $0.normalizedBaseURL) })
        let nameByInstanceID = Dictionary(uniqueKeysWithValues: instances.map { ($0.id, $0.name) })

        var order: [String] = []
        var groupedByKey: [String: [CachedLocation]] = [:]
        for location in locations {
            let baseURL = baseURLByInstanceID[location.instanceID] ?? location.instanceID.uuidString
            let key = "\(baseURL)#\(location.serverID)"
            if groupedByKey[key] == nil { order.append(key) }
            groupedByKey[key, default: []].append(location)
        }

        return order.compactMap { key in
            guard let group = groupedByKey[key], let representative = group.first else { return nil }
            let names = group.map { nameByInstanceID[$0.instanceID] ?? "" }.filter { !$0.isEmpty }
            return MergedItem(location: representative, instanceNames: names)
        }
    }
}

/// The left color edge of a merged row: only when exactly one instance owns the entry. An entry that several
/// instances share (a merged news post or location) gets no edge, just a badge per instance.
public enum InstanceEdge {
    public static func name(for instanceNames: [String]) -> String? {
        instanceNames.count == 1 ? instanceNames.first : nil
    }
}
