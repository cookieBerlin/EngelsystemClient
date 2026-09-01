import Foundation
import SwiftData

@Model
public final class CachedWorklog {
    // Composite unique key prevents collision across instances with the same server-assigned ID
    @Attribute(.unique) public var uid: String
    public var serverID: Int
    public var instanceID: UUID

    public var workLogDescription: String
    public var hours: Double
    public var createdByID: Int
    public var createdByName: String?
    public var workedAt: Date
    public var createdAt: Date?
    public var updatedAt: Date?

    public var cachedAt: Date

    @Relationship public var instance: Instance?

    public init(
        serverID: Int,
        instanceID: UUID,
        workLogDescription: String,
        hours: Double,
        createdByID: Int,
        createdByName: String? = nil,
        workedAt: Date,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.uid = "\(instanceID.uuidString):\(serverID)"
        self.serverID = serverID
        self.instanceID = instanceID
        self.workLogDescription = workLogDescription
        self.hours = hours
        self.createdByID = createdByID
        self.createdByName = createdByName
        self.workedAt = workedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.cachedAt = Date()
    }
}

public extension CachedWorklog {
    func updateCacheTimestamp() { cachedAt = Date() }

    static func sortedByDate(_ worklogs: [CachedWorklog]) -> [CachedWorklog] {
        worklogs.sorted { $0.workedAt > $1.workedAt }
    }

    static func totalHours(_ worklogs: [CachedWorklog]) -> Double {
        worklogs.reduce(0) { $0 + $1.hours }
    }
}
