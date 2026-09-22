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

    /// One news post that survived `mergedAcrossServers`, paired with the name of
    /// *every* active `Instance` whose own cached copy contributed to it — not just
    /// the one `item` happens to belong to. Lets the UI show a badge per instance the
    /// post actually appears on (2026-09-22, user-reported: after deduplication only
    /// one instance's badge was shown, even when the post existed on both).
    struct MergedItem: Identifiable {
        public let item: CachedNews
        public let instanceNames: [String]
        public var id: String { item.uid }
    }

    /// Collapses news items that came from *different* `Instance`s pointing at the
    /// *same* actual Engelsystem server — e.g. one physical event configured twice
    /// under two different user accounts/API keys (multi-active-instance concept,
    /// CLAUDE.md). Each `Instance` syncs and caches news independently (`CachedNews
    /// .uid` includes `instanceID`), so the same real-world news post ends up stored
    /// once per instance and would otherwise show up more than once in a merged,
    /// cross-instance list (2026-09-22, user-reported).
    ///
    /// A news post is server-assigned (`serverID`), not globally unique across
    /// servers, so the merge key is the pair (server base URL, `serverID`) — resolved
    /// via `instances`, not just `instanceID` — since that's what actually identifies
    /// "the same post" across two `Instance`s. The *content* of the surviving
    /// `MergedItem.item` is the first occurrence per key, so callers should
    /// sort/order `items` deterministically first (e.g. via `sortedByRecency`) — which
    /// representative's content survives is otherwise arbitrary, but harmless, since
    /// duplicates share the same real content; `instanceNames` collects every
    /// contributing instance regardless, so no instance's badge gets lost.
    static func mergedAcrossServers(_ items: [CachedNews], instances: [Instance]) -> [MergedItem] {
        let baseURLByInstanceID = Dictionary(uniqueKeysWithValues: instances.map { ($0.id, $0.normalizedBaseURL) })
        let nameByInstanceID = Dictionary(uniqueKeysWithValues: instances.map { ($0.id, $0.name) })

        var order: [String] = []
        var groupedByKey: [String: [CachedNews]] = [:]
        for item in items {
            let baseURL = baseURLByInstanceID[item.instanceID] ?? item.instanceID.uuidString
            let key = "\(baseURL)#\(item.serverID)"
            if groupedByKey[key] == nil { order.append(key) }
            groupedByKey[key, default: []].append(item)
        }

        return order.compactMap { key in
            guard let group = groupedByKey[key], let representative = group.first else { return nil }
            let names = group.map { nameByInstanceID[$0.instanceID] ?? "" }.filter { !$0.isEmpty }
            return MergedItem(item: representative, instanceNames: names)
        }
    }
}
