import Foundation
import UserNotifications

/// Thin protocol over the parts of `UNUserNotificationCenter` that
/// `NotificationScheduler` uses, so tests can inject a fake instead of touching
/// the real system notification center.
public protocol NotificationCenterScheduling {
    /// Just the status (not `UNNotificationSettings`, which has no public initializer and
    /// so couldn't be faked in tests).
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

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

    /// Fallback lead time when no `NotificationLeadTimeSettings` row exists yet for
    /// this platform (e.g. first launch) — this is the *only* place the number `15`
    /// is hardcoded; `NotificationLeadTimeSettings.defaultLeadTimesMinutes` is derived
    /// from it.
    public static let defaultMinutesBefore = 15

    /// Presets offered in Settings' "Add Reminder" menu — a fixed list, not free-form
    /// entry, matching the picker this replaced (2026-09-22, "multiple reminders"
    /// feature — see `NotificationLeadTimeSettings`, which now stores *which subset*
    /// of these is active, as a list instead of a single value).
    public static let availableLeadTimesInMinutes = [5, 10, 15, 30, 60]

    /// One identifier per (shift, lead time) pair — 2026-09-22, changed from a plain
    /// per-shift identifier so a single shift can have more than one reminder
    /// scheduled independently (e.g. one 60 minutes before, another 15 minutes
    /// before).
    public static func identifier(for shift: CachedShift, minutesBefore: Int) -> String {
        identifierPrefix + shift.uid + "-" + String(minutesBefore)
    }

    /// Pure planning step (no I/O): which upcoming shifts need a notification, when,
    /// and for which of the configured lead times. Kept separate from
    /// `syncNotifications` so it's unit-testable without a notification center at all.
    public static func plan(for shifts: [CachedShift], leadTimes: [Int]) -> [PlannedNotification] {
        plannedPairs(for: shifts, leadTimes: leadTimes).map(\.item)
    }

    /// `plan`, but keeping each planned notification paired with its shift, so
    /// `syncNotifications` never has to look a shift up again by UID.
    static func plannedPairs(for shifts: [CachedShift], leadTimes: [Int]) -> [(item: PlannedNotification, shift: CachedShift)] {
        CachedShift.upcomingShifts(from: shifts).flatMap { shift in
            leadTimes.compactMap { minutesBefore -> (item: PlannedNotification, shift: CachedShift)? in
                guard let fireDate = shift.notificationDate(minutesBefore: minutesBefore) else { return nil }
                let item = PlannedNotification(
                    identifier: identifier(for: shift, minutesBefore: minutesBefore),
                    shiftUID: shift.uid,
                    fireDate: fireDate
                )
                return (item, shift)
            }
        }
    }

    static func body(for shift: CachedShift) -> String {
        if let locationName = shift.locationName {
            return "Starts at \(shift.formattedTimeRange()) · \(locationName)"
        }
        return "Starts at \(shift.formattedTimeRange())"
    }

    private let center: NotificationCenterScheduling

    /// The real-center convenience initializer, `init()`, lives in `SystemNotificationCenter.swift`.
    public init(center: NotificationCenterScheduling) {
        self.center = center
    }

    /// `-skipNotificationPrompt YES` (a launch argument, i.e. a defaults key) makes Debug builds neither ask for nor
    /// use notification permission — so the screenshot script's Watch scene isn't covered by the system prompt.
    /// Always `false` in Release builds.
    public static let skipPromptDefaultsKey = "skipNotificationPrompt"

    static func shouldSkipPrompt(in defaults: UserDefaults) -> Bool {
        #if DEBUG
        defaults.bool(forKey: skipPromptDefaultsKey)
        #else
        false
        #endif
    }

    /// Requests notification authorization if not already determined. Returns whether
    /// notifications are (now) allowed.
    @discardableResult
    public func requestAuthorizationIfNeeded() async -> Bool {
        if Self.shouldSkipPrompt(in: .standard) { return false }
        switch await center.authorizationStatus() {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            // 2026-09-23, user-requested "check the data flow for logging gaps": the
            // one-time authorization prompt's outcome was previously invisible — the
            // first thing worth checking for a "why don't I get notifications" report.
            DebugLog.log("Notification authorization \(granted ? "granted" : "denied") after prompting")
            return granted
        case .denied:
            DebugLog.log("Notification authorization is denied", level: .warning)
            return false
        @unknown default:
            return false
        }
    }

    /// Schedules a notification for every upcoming shift that doesn't have one yet,
    /// and cancels any previously scheduled shift notification that's no longer
    /// planned (the shift became past, disappeared from the synced set, or its lead
    /// time was removed from Settings). `leadTimes` is read fresh by the caller on
    /// every sync (rather than fixed at init time) so a change to Settings' reminder
    /// list takes effect on the very next sync — including a removed lead time: it
    /// simply stops appearing in `plan(...)`, so the existing "cancel what's no
    /// longer planned" logic below prunes it without any extra code.
    public func syncNotifications(for shifts: [CachedShift], leadTimes: [Int]) async {
        let planned = Self.plannedPairs(for: shifts, leadTimes: leadTimes)
        let plannedIdentifiers = Set(planned.map(\.item.identifier))

        let pending = await center.pendingNotificationRequests()
        let staleIdentifiers = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) && !plannedIdentifiers.contains($0) }
        if !staleIdentifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: staleIdentifiers)
        }

        let alreadyScheduled = Set(pending.map(\.identifier))
        for (item, shift) in planned where !alreadyScheduled.contains(item.identifier) {
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
