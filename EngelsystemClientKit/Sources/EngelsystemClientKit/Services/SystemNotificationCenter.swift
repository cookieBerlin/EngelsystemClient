import Foundation
import UserNotifications

/// Thin adapter over the real `UNUserNotificationCenter` — kept in its own file because
/// the real center crashes under `swift test`'s CLI harness (no host app bundle), so
/// none of this can run in unit tests. All logic takes a `NotificationCenterScheduling`
/// and is tested with fakes. Excluded from the coverage gate (standing approval for
/// thin adapters, owner, 2026-10-12).
struct SystemNotificationCenter: NotificationCenterScheduling {
    private var center: UNUserNotificationCenter { .current() }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        await center.pendingNotificationRequests()
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

public extension NotificationScheduler {
    init() { self.init(center: SystemNotificationCenter()) }
}

public extension NewsNotifier {
    init() { self.init(center: SystemNotificationCenter()) }
}
