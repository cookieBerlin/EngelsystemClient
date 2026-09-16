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

    // No relationship to Instance — it lives in a separate, CloudKit-backed
    // ModelConfiguration; see Instance.swift. Callers filter by `instanceID` instead.

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

// MARK: - Mapping from the generated `News` DTO

public extension CachedNews {
    convenience init(news: News, instanceID: UUID) {
        self.init(
            serverID: news.id,
            instanceID: instanceID,
            title: news.name,
            text: Self.sanitizedText(from: news.text),
            isMeeting: news.isMeeting,
            isPinned: news.isPinned,
            isHighlighted: news.isHighlighted,
            createdAt: news.createdAt,
            updatedAt: news.updatedAt,
            url: news.url
        )
    }

    /// Updates all fields from a freshly fetched `News` DTO (used by `NewsSyncService`
    /// when a cached row already exists for this news item).
    func apply(_ news: News) {
        title = news.name
        text = Self.sanitizedText(from: news.text)
        isMeeting = news.isMeeting
        isPinned = news.isPinned
        isHighlighted = news.isHighlighted
        createdAt = news.createdAt
        updatedAt = news.updatedAt
        url = news.url
        updateCacheTimestamp()
    }

    static func uid(instanceID: UUID, serverID: Int) -> String {
        "\(instanceID.uuidString):\(serverID)"
    }

    /// The API docs say the text "might include a `[more]` tag to be used as a
    /// separator which must be removed from the text when shown" — since we always
    /// show the full text (no truncated preview), simply removing the marker satisfies
    /// that. Also trims the whitespace/newlines the tag typically sits between.
    static func sanitizedText(from rawText: String) -> String {
        rawText
            .replacingOccurrences(of: "[more]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
