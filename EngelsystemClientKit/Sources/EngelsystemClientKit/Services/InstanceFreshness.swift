import Foundation

/// How fresh the cached data of one active instance is, as the footer of the main page shows it
///. Pure value logic: the page only lays out `text`, `systemImage` and `level`.
public struct InstanceFreshness: Equatable, Identifiable {
    public enum Level: Equatable {
        /// Synced less than `staleAfter` ago.
        case current
        /// Synced `staleAfter` or longer ago.
        case stale
        /// Nothing cached yet.
        case neverSynced
    }

    /// From this age on the data counts as outdated.
    public static let staleAfter: TimeInterval = 12 * 3600

    public let instanceID: UUID
    public let instanceName: String
    public let lastSync: Date?
    public let level: Level
    /// The instance's name leads the text; only needed when more than one instance is listed.
    public let showsName: Bool
    private let now: Date

    public var id: UUID { instanceID }

    public init(instanceID: UUID, instanceName: String, lastSync: Date?, showsName: Bool, now: Date = Date()) {
        self.instanceID = instanceID
        self.instanceName = instanceName
        self.lastSync = lastSync
        self.showsName = showsName
        self.now = now
        if let lastSync {
            level = now.timeIntervalSince(lastSync) >= Self.staleAfter ? .stale : .current
        } else {
            level = .neverSynced
        }
    }

    /// One row per active instance; names are shown only when there is more than one.
    public static func rows(
        for instances: [Instance], lastSync: (Instance) -> Date?, now: Date = Date()
    ) -> [InstanceFreshness] {
        let active = instances.filter(\.isActive)
        return active.map {
            InstanceFreshness(
                instanceID: $0.id, instanceName: $0.name, lastSync: lastSync($0), showsName: active.count > 1, now: now)
        }
    }

    /// The symbol that carries the state besides the colour.
    public var systemImage: String {
        level == .current ? "checkmark.circle" : "exclamationmark.triangle.fill"
    }

    /// Whether tapping the row (which refreshes the instance) is worth pointing out.
    public var needsRefresh: Bool { level != .current }

    /// "Home: updated 3 hours ago", "Updated 3 hours ago", "Home: not synced yet – tap to refresh".
    public var text: String {
        let age: String
        switch level {
        case .neverSynced:
            age = "not synced yet"
        case .current, .stale:
            age = "updated " + Self.relative(lastSync, from: now)
        }
        let sentence = showsName ? "\(instanceName): \(age)" : age.prefix(1).uppercased() + age.dropFirst()
        return needsRefresh ? sentence + " – tap to refresh" : sentence
    }

    /// What VoiceOver says: the state in words first, because the symbol is not read out.
    public var accessibilityText: String {
        switch level {
        case .current: return "Up to date. " + text
        case .stale: return "Warning, data is outdated. " + text
        case .neverSynced: return "Warning, no data yet. " + text
        }
    }

    private static func relative(_ date: Date?, from now: Date) -> String {
        guard let date, now.timeIntervalSince(date) >= 60 else { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
