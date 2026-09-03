import Foundation
import SwiftData

/// The signed-in user's own angel type memberships for an instance (`GET
/// /users/{id}/angeltypes`) — distinct from the instance-wide angel type catalog
/// (`APIClient.fetchAngelTypes`), which lists every angel type regardless of who's a
/// member. Shown on the Profile screen per CLAUDE.md's Phase 1 scope ("profile, angel
/// types, worklogs").
@Model
public final class CachedAngelTypeMembership {
    // Composite unique key prevents collision across instances with the same server-assigned ID
    @Attribute(.unique) public var uid: String
    public var serverID: Int
    public var instanceID: UUID

    // Flattened from the API's angeltype Reference
    public var angelTypeName: String?

    public var confirmed: Bool
    public var supporter: Bool

    public var cachedAt: Date

    @Relationship public var instance: Instance?

    public init(
        serverID: Int,
        instanceID: UUID,
        angelTypeName: String? = nil,
        confirmed: Bool,
        supporter: Bool
    ) {
        self.uid = "\(instanceID.uuidString):\(serverID)"
        self.serverID = serverID
        self.instanceID = instanceID
        self.angelTypeName = angelTypeName
        self.confirmed = confirmed
        self.supporter = supporter
        self.cachedAt = Date()
    }
}

// MARK: - Mapping from the generated `UserAngelType` DTO

public extension CachedAngelTypeMembership {
    convenience init(membership: UserAngelType, instanceID: UUID) {
        self.init(
            serverID: membership.angeltype.id,
            instanceID: instanceID,
            angelTypeName: membership.angeltype.name,
            confirmed: membership.confirmed,
            supporter: membership.supporter
        )
    }

    /// Updates all fields from a freshly fetched `UserAngelType` DTO (used by
    /// `ProfileSyncService` when a cached row already exists for this membership).
    func apply(_ membership: UserAngelType) {
        angelTypeName = membership.angeltype.name
        confirmed = membership.confirmed
        supporter = membership.supporter
        updateCacheTimestamp()
    }

    static func uid(instanceID: UUID, serverID: Int) -> String {
        "\(instanceID.uuidString):\(serverID)"
    }
}

public extension CachedAngelTypeMembership {
    func updateCacheTimestamp() { cachedAt = Date() }

    static func sortedByName(_ memberships: [CachedAngelTypeMembership]) -> [CachedAngelTypeMembership] {
        memberships.sorted { ($0.angelTypeName ?? "") < ($1.angelTypeName ?? "") }
    }
}
