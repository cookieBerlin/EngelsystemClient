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

// MARK: - Mapping from the generated `Worklog` DTO

public extension CachedWorklog {
    convenience init(worklog: Worklog, instanceID: UUID) {
        self.init(
            serverID: worklog.id,
            instanceID: instanceID,
            workLogDescription: worklog.description,
            hours: Double(worklog.hours),
            createdByID: worklog.createdBy.id,
            createdByName: worklog.createdBy.name,
            workedAt: worklog.workedAt,
            createdAt: worklog.createdAt,
            updatedAt: worklog.updatedAt
        )
    }

    /// Updates all fields from a freshly fetched `Worklog` DTO (used by `ProfileSyncService`
    /// when a cached row already exists for this worklog).
    func apply(_ worklog: Worklog) {
        workLogDescription = worklog.description
        hours = Double(worklog.hours)
        createdByID = worklog.createdBy.id
        createdByName = worklog.createdBy.name
        workedAt = worklog.workedAt
        createdAt = worklog.createdAt
        updatedAt = worklog.updatedAt
        updateCacheTimestamp()
    }

    static func uid(instanceID: UUID, serverID: Int) -> String {
        "\(instanceID.uuidString):\(serverID)"
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
