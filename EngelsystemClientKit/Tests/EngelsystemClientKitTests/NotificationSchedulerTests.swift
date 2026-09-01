import Foundation
import UserNotifications
import Testing
@testable import EngelsystemClientKit

private final class FakeNotificationCenter: NotificationCenterScheduling, @unchecked Sendable {
    var authorizationStatus: UNAuthorizationStatus = .authorized
    var addedRequests: [UNNotificationRequest] = []
    private var pending: [UNNotificationRequest] = []

    func notificationSettings() async -> UNNotificationSettings {
        // UNNotificationSettings has no public initializer, so tests drive authorization
        // via `requestAuthorizationIfNeeded`'s return value instead of this method's result
        // when they need a specific status; callers that only care about scheduling behavior
        // can ignore it.
        fatalError("notificationSettings() is not used by the tests in this file")
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        authorizationStatus == .authorized
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        pending
    }

    func add(_ request: UNNotificationRequest) async throws {
        addedRequests.append(request)
        pending.append(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        pending.removeAll { identifiers.contains($0.identifier) }
    }
}

private func makeShift(id: Int, hoursFromNow: Double, title: String = "Shift") -> CachedShift {
    let now = Date()
    return CachedShift(
        serverID: id,
        instanceID: UUID(),
        title: title,
        startsAt: now.addingTimeInterval(hoursFromNow * 3600),
        endsAt: now.addingTimeInterval((hoursFromNow + 2) * 3600),
        locationID: 1,
        locationName: "Heaven",
        shiftTypeID: 1,
        url: "https://example.org/shifts/\(id)"
    )
}

@Test func notificationSchedulerPlansOnlyUpcomingShiftsWithFutureFireDate() {
    let upcoming = makeShift(id: 1, hoursFromNow: 2)
    let past = makeShift(id: 2, hoursFromNow: -2)
    // Starts in 10 minutes — with a 15-minute lead time, the fire date is already in the past.
    let tooSoon = makeShift(id: 3, hoursFromNow: 10.0 / 60.0)

    let planned = NotificationScheduler.plan(for: [upcoming, past, tooSoon], minutesBefore: 15)

    #expect(planned.count == 1)
    #expect(planned.first?.shiftUID == upcoming.uid)
    #expect(planned.first?.identifier == NotificationScheduler.identifier(for: upcoming))
}

@Test func notificationSchedulerSyncSchedulesNewAndCancelsStale() async {
    let center = FakeNotificationCenter()
    let scheduler = NotificationScheduler(center: center, minutesBefore: 15)

    let shiftA = makeShift(id: 1, hoursFromNow: 2, title: "Info Desk")
    let shiftB = makeShift(id: 2, hoursFromNow: 4, title: "Set-up")

    await scheduler.syncNotifications(for: [shiftA, shiftB])
    #expect(center.addedRequests.count == 2)
    #expect(Set(center.addedRequests.map(\.identifier)) == [
        NotificationScheduler.identifier(for: shiftA),
        NotificationScheduler.identifier(for: shiftB),
    ])

    // Re-syncing with only shiftA left should cancel shiftB's notification and not
    // re-add shiftA's (it's already scheduled).
    await scheduler.syncNotifications(for: [shiftA])
    let stillPending = await center.pendingNotificationRequests()
    #expect(stillPending.map(\.identifier) == [NotificationScheduler.identifier(for: shiftA)])
    #expect(center.addedRequests.count == 2) // no duplicate add call for shiftA
}

@Test func notificationSchedulerDoesNotDuplicateAnAlreadyScheduledShift() async {
    let center = FakeNotificationCenter()
    let scheduler = NotificationScheduler(center: center, minutesBefore: 15)
    let shift = makeShift(id: 1, hoursFromNow: 2)

    await scheduler.syncNotifications(for: [shift])
    await scheduler.syncNotifications(for: [shift])

    #expect(center.addedRequests.count == 1)
}
