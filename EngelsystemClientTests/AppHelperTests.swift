import Foundation
import SwiftData
import SwiftUI
import UserNotifications
import Testing
import EngelsystemClientKit
@testable import EngelsystemClient

private final class RecordingScheduler: BackgroundTaskScheduling {
    var cancelled: [String] = []
    var submitted: [(identifier: String, date: Date)] = []
    var failure: Error?
    func cancelRefresh(identifier: String) { cancelled.append(identifier) }
    func submitRefresh(identifier: String, earliestBeginDate: Date) throws {
        if let failure { throw failure }
        submitted.append((identifier, earliestBeginDate))
    }
}

private final class QuietCenter: NotificationCenterScheduling, @unchecked Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus { .denied }
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { false }
    func pendingNotificationRequests() async -> [UNNotificationRequest] { [] }
    func add(_ request: UNNotificationRequest) async throws {}
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {}
}

struct BackgroundSyncSchedulerTests {
    private struct Rejected: Error {}

    @Test func manualIntervalCancelsAndSchedulesNothing() {
        let scheduler = RecordingScheduler()
        BackgroundSyncScheduler.scheduleNext(using: scheduler, interval: .manual, now: Date())
        #expect(scheduler.cancelled == [BackgroundSyncScheduler.taskIdentifier])
        #expect(scheduler.submitted.isEmpty)
    }

    @Test func aTimedIntervalSubmitsTheNextRefreshAtNowPlusTheInterval() {
        let scheduler = RecordingScheduler()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        BackgroundSyncScheduler.scheduleNext(using: scheduler, interval: .minutes30, now: now)
        #expect(scheduler.submitted.count == 1)
        #expect(scheduler.submitted[0].identifier == BackgroundSyncScheduler.taskIdentifier)
        #expect(scheduler.submitted[0].date == now.addingTimeInterval(1800))
    }

    @Test func aRejectedSubmissionIsLoggedNotThrown() {
        let scheduler = RecordingScheduler()
        scheduler.failure = Rejected()
        BackgroundSyncScheduler.scheduleNext(using: scheduler, interval: .minutes15, now: Date())
        #expect(scheduler.submitted.isEmpty)
    }

    @Test @MainActor func runSyncSyncsActiveInstancesThenSchedulesTheNextRun() async throws {
        let schema = Schema([
            Instance.self, NotificationLeadTimeSettings.self, CachedShift.self, CachedNews.self, CachedUser.self,
            CachedWorklog.self, CachedAngelTypeMembership.self, CachedLocation.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let context = ModelContext(try ModelContainer(for: schema, configurations: [config]))
        let ref = "bg-sync-\(UUID().uuidString)"
        try LocalKeychainStore().save(apiKey: "demo", for: ref)
        defer { try? LocalKeychainStore().deleteAPIKey(for: ref) }
        context.insert(Instance(name: "Demo", baseURL: Instance.demoBaseURL, apiKeyKeychainRef: ref))
        context.insert(Instance(name: "Off", baseURL: Instance.demoBaseURL, apiKeyKeychainRef: ref, isActive: false))
        let center = QuietCenter()
        let coordinator = AppSyncCoordinator(
            notificationScheduler: NotificationScheduler(center: center), newsNotifier: NewsNotifier(center: center)
        )
        let scheduler = RecordingScheduler()

        let succeeded = await BackgroundSyncScheduler.runSync(
            in: context, coordinator: coordinator, scheduler: scheduler, interval: .minutes60
        )

        #expect(succeeded)
        #expect(try context.fetch(FetchDescriptor<CachedShift>()).count == 2)
        #expect(scheduler.submitted.count == 1)
        #expect(DeviceSyncPreferences.lastBackgroundSyncDate() != nil)
    }
}

struct NewsMarkdownRendererExtraTests {
    @Test func headersAreRenderedBoldAndLarger() {
        let result = NewsMarkdownRenderer.render("# Title\n\nBody")
        #expect(String(result.characters).hasPrefix("Title"))
        #expect(result.runs.contains { $0.font != nil })
    }

    @Test func blockQuotesAreRenderedSecondary() {
        let result = NewsMarkdownRenderer.render("> quoted")
        #expect(result.runs.contains { $0.foregroundColor != nil })
    }

    @Test func textWithoutBlockStructureIsRenderedAsIs() {
        let result = NewsMarkdownRenderer.render("plain", parse: { AttributedString($0) })
        #expect(String(result.characters) == "plain")
    }

    @Test func aParseFailureFallsBackToThePlainText() {
        struct Boom: Error {}
        let result = NewsMarkdownRenderer.render("**raw**", parse: { _ in throw Boom() })
        #expect(String(result.characters) == "**raw**")
    }
}
