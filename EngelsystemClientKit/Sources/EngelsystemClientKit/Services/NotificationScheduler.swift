import Foundation
import UserNotifications

/// Thin protocol over the parts of `UNUserNotificationCenter` that
/// `NotificationScheduler` uses, so tests can inject a fake instead of touching
/// the real system notification center.
public protocol NotificationCenterScheduling {
    func notificationSettings() async -> UNNotificationSettings
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

extension UNUserNotificationCenter: NotificationCenterScheduling {}

/// Schedules local reminders (no server push — the API doesn't support it) before
/// each upcoming shift starts, generated from the shifts currently in `CachedShift`.
/// Used identically by the iOS app and the Watch app, per CLAUDE.md.
public struct NotificationScheduler {
    public struct PlannedNotification: Equatable {
        public let identifier: String
        public let shiftUID: String
        public let fireDate: Date
    }

    public static let identifierPrefix = "shift-notification-"

    public static func identifier(for shift: CachedShift) -> String {
        identifierPrefix + shift.uid
    }

    /// Pure planning step (no I/O): which upcoming shifts need a notification, and when.
    /// Kept separate from `syncNotifications` so it's unit-testable without a
    /// notification center at all.
    public static func plan(for shifts: [CachedShift], minutesBefore: Int) -> [PlannedNotification] {
        CachedShift.upcomingShifts(from: shifts).compactMap { shift in
            guard let fireDate = shift.notificationDate(minutesBefore: minutesBefore) else { return nil }
            return PlannedNotification(identifier: identifier(for: shift), shiftUID: shift.uid, fireDate: fireDate)
        }
    }

    static func body(for shift: CachedShift) -> String {
        if let locationName = shift.locationName {
            return "Starts at \(shift.formattedTimeRange()) · \(locationName)"
        }
        return "Starts at \(shift.formattedTimeRange())"
    }

    private let center: NotificationCenterScheduling
    private let minutesBefore: Int

    public init(center: NotificationCenterScheduling = UNUserNotificationCenter.current(), minutesBefore: Int = 15) {
        self.center = center
        self.minutesBefore = minutesBefore
    }

    /// Requests notification authorization if not already determined. Returns whether
    /// notifications are (now) allowed.
    @discardableResult
    public func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    /// Schedules a notification for every upcoming shift that doesn't have one yet,
    /// and cancels any previously scheduled shift notification that's no longer planned
    /// (the shift became past, or disappeared from the synced set).
    public func syncNotifications(for shifts: [CachedShift]) async {
        let planned = Self.plan(for: shifts, minutesBefore: minutesBefore)
        let plannedIdentifiers = Set(planned.map(\.identifier))

        let pending = await center.pendingNotificationRequests()
        let staleIdentifiers = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) && !plannedIdentifiers.contains($0) }
        if !staleIdentifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: staleIdentifiers)
        }

        let alreadyScheduled = Set(pending.map(\.identifier))
        for item in planned where !alreadyScheduled.contains(item.identifier) {
            guard let shift = shifts.first(where: { $0.uid == item.shiftUID }) else { continue }

            let content = UNMutableNotificationContent()
            content.title = shift.title
            content.body = Self.body(for: shift)
            content.sound = .default

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: item.fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }
}
