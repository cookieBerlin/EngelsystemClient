import Foundation
import UserNotifications
import Testing
@testable import EngelsystemClientKit

private final class StatusCenter: NotificationCenterScheduling, @unchecked Sendable {
    var status: UNAuthorizationStatus
    var grantOnRequest = true
    var requested = 0
    var added: [UNNotificationRequest] = []
    var failAdd = false
    struct AddFailure: Error {}

    init(_ status: UNAuthorizationStatus) { self.status = status }

    func authorizationStatus() async -> UNAuthorizationStatus { status }
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        requested += 1
        if !grantOnRequest { throw AddFailure() }
        return true
    }
    func pendingNotificationRequests() async -> [UNNotificationRequest] { added }
    func add(_ request: UNNotificationRequest) async throws {
        if failAdd { throw AddFailure() }
        added.append(request)
    }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {}
}

@Suite(.serialized)
struct NotificationServicesTests {
    private let instanceID = UUID()

    // MARK: NotificationScheduler authorization

    @Test func authorizedAndProvisionalStatusesAllowNotifications() async {
        for status in [UNAuthorizationStatus.authorized, .provisional] {
            let center = StatusCenter(status)
            #expect(await NotificationScheduler(center: center).requestAuthorizationIfNeeded())
            #expect(center.requested == 0)
        }
    }

    @Test func anUndeterminedStatusPromptsOnceAndReturnsTheAnswer() async {
        let granted = StatusCenter(.notDetermined)
        #expect(await NotificationScheduler(center: granted).requestAuthorizationIfNeeded())
        #expect(granted.requested == 1)

        let failing = StatusCenter(.notDetermined)
        failing.grantOnRequest = false
        #expect(await NotificationScheduler(center: failing).requestAuthorizationIfNeeded() == false)
    }

    @Test func aDeniedStatusDoesNotPromptAndReturnsFalse() async {
        let center = StatusCenter(.denied)
        #expect(await NotificationScheduler(center: center).requestAuthorizationIfNeeded() == false)
        #expect(center.requested == 0)
    }

    @Test func anUnknownFutureStatusIsTreatedAsNotAllowed() async throws {
        let future = try #require(UNAuthorizationStatus(rawValue: 99))
        #expect(await NotificationScheduler(center: StatusCenter(future)).requestAuthorizationIfNeeded() == false)
    }

    @Test func shiftBodyMentionsTheLocationOnlyWhenKnown() {
        func shift(location: String?) -> CachedShift {
            CachedShift(
                serverID: 1, instanceID: instanceID, title: "T", startsAt: Date(), endsAt: Date().addingTimeInterval(3600),
                locationID: 1, locationName: location, shiftTypeID: 1, url: "u"
            )
        }
        #expect(NotificationScheduler.body(for: shift(location: "Hall A")).hasSuffix("· Hall A"))
        #expect(!NotificationScheduler.body(for: shift(location: nil)).contains("·"))
    }

    // MARK: NewsNotifier

    private func news(_ id: Int, title: String = "Title", text: String = "Body") -> CachedNews {
        CachedNews(
            serverID: id, instanceID: instanceID, title: title, text: text, isMeeting: false,
            isPinned: false, isHighlighted: false, createdAt: Date(), url: "u"
        )
    }

    @Test func newsContentIsNilForNoItemsAndSummarizesOneOrMany() {
        #expect(NewsNotifier.content(for: [], instanceName: nil) == nil)
        let one = NewsNotifier.content(for: [news(1, title: "Hi", text: "Preview [more] rest")], instanceName: "Event")
        #expect(one == NewsNotifier.Content(title: "Hi", body: "Event — Preview"))
        let noName = NewsNotifier.content(for: [news(1)], instanceName: nil)
        #expect(noName?.body == "Body")
        let many = NewsNotifier.content(for: [news(1, title: "A"), news(2, title: "B")], instanceName: "Ignored")
        #expect(many == NewsNotifier.Content(title: "2 New Announcements", body: "A, B"))
    }

    @Test func newsNotificationsDefaultToOnAndCanBeDisabled() {
        let defaults = UserDefaults(suiteName: "NewsNotifierTests-\(UUID().uuidString)")!
        #expect(NewsNotifier.isEnabled(in: defaults))
        defaults.set(false, forKey: NewsNotifier.enabledUserDefaultsKey)
        #expect(NewsNotifier.isEnabled(in: defaults) == false)
    }

    @Test func notifyPostsOneNotificationAndNothingForNoItems() async {
        let center = StatusCenter(.authorized)
        let notifier = NewsNotifier(center: center)
        await notifier.notify(newItems: [], instanceName: nil)
        #expect(center.added.isEmpty)
        UserDefaults.standard.removeObject(forKey: NewsNotifier.enabledUserDefaultsKey)
        await notifier.notify(newItems: [news(1), news(2)], instanceName: nil)
        #expect(center.added.count == 1)
        #expect(center.added[0].identifier.hasPrefix(NewsNotifier.identifierPrefix))
    }

    @Test func notifyIsSkippedWhenDisabledAndSurvivesAFailingCenter() async {
        let center = StatusCenter(.authorized)
        let notifier = NewsNotifier(center: center)
        UserDefaults.standard.set(false, forKey: NewsNotifier.enabledUserDefaultsKey)
        await notifier.notify(newItems: [news(1)], instanceName: nil)
        #expect(center.added.isEmpty)

        UserDefaults.standard.set(true, forKey: NewsNotifier.enabledUserDefaultsKey)
        center.failAdd = true
        await notifier.notify(newItems: [news(1)], instanceName: nil)
        #expect(center.added.isEmpty)
        UserDefaults.standard.removeObject(forKey: NewsNotifier.enabledUserDefaultsKey)
    }
}
