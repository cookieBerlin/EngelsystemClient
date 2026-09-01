import Foundation
import SwiftData

@Model
public final class CachedNews {
    // Composite unique key prevents collision across instances with the same server-assigned ID
    @Attribute(.unique) public var uid: String
    public var serverID: Int
    public var instanceID: UUID

    public var title: String
    public var text: String
    public var isMeeting: Bool
    public var isPinned: Bool
    public var isHighlighted: Bool
    public var createdAt: Date
    public var updatedAt: Date?

    public var url: String
    public var cachedAt: Date

    @Relationship public var instance: Instance?

    public init(
        serverID: Int,
        instanceID: UUID,
        title: String,
        text: String,
        isMeeting: Bool,
        isPinned: Bool,
        isHighlighted: Bool,
        createdAt: Date,
        updatedAt: Date? = nil,
        url: String
    ) {
        self.uid = "\(instanceID.uuidString):\(serverID)"
        self.serverID = serverID
        self.instanceID = instanceID
        self.title = title
        self.text = text
        self.isMeeting = isMeeting
        self.isPinned = isPinned
        self.isHighlighted = isHighlighted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.url = url
        self.cachedAt = Date()
    }
}

public extension CachedNews {
    func updateCacheTimestamp() { cachedAt = Date() }

    static func sortedByRecency(_ news: [CachedNews]) -> [CachedNews] {
        news.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.createdAt > rhs.createdAt
        }
    }
}
