import Foundation

/// A minimal, non-sensitive snapshot of the next upcoming shift — deliberately excludes
/// the API key or anything else sensitive, since it's written to an App Group container
/// shared with the Watch complication extension (a separate process that has no access
/// to the Keychain item the main Watch app uses).
public struct NextShiftSnapshot: Codable, Equatable, Sendable {
    public let title: String
    public let startsAt: Date
    public let endsAt: Date
    public let locationName: String?

    public init(title: String, startsAt: Date, endsAt: Date, locationName: String?) {
        self.title = title
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.locationName = locationName
    }
}

/// Reads/writes `NextShiftSnapshot` to the App Group container shared between the Watch
/// app and its complication (`Services/NotificationScheduler`-style: the Watch app writes
/// after every sync, the complication's timeline provider only ever reads).
public struct NextShiftSnapshotStore {
    public static let defaultAppGroupID = "group.de.engelsystem.shared"

    private static let key = "nextShiftSnapshot"

    private let defaults: UserDefaults?

    public init(appGroupID: String = NextShiftSnapshotStore.defaultAppGroupID) {
        self.defaults = UserDefaults(suiteName: appGroupID)
    }

    /// Pass `nil` to clear the snapshot (e.g. when there's no upcoming shift).
    public func save(_ snapshot: NextShiftSnapshot?) {
        guard let defaults else { return }
        guard let snapshot, let data = try? JSONEncoder().encode(snapshot) else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        defaults.set(data, forKey: Self.key)
    }

    public func load() -> NextShiftSnapshot? {
        guard let defaults, let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(NextShiftSnapshot.self, from: data)
    }
}
