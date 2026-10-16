import CloudKit
import Foundation
import SwiftData
import UserNotifications
import Testing
@testable import EngelsystemClientKit

private final class MemoryKeyStore: APIKeyStore, @unchecked Sendable {
    var keys: [String: String] = [:]
    struct Missing: Error {}
    func save(apiKey: String, for reference: String) throws { keys[reference] = apiKey }
    func loadAPIKey(for reference: String) throws -> String {
        guard let key = keys[reference] else { throw Missing() }
        return key
    }
    func deleteAPIKey(for reference: String) throws { keys[reference] = nil }
}

@MainActor
private func makeContext() throws -> ModelContext {
    let schema = Schema([
        Instance.self, NotificationLeadTimeSettings.self, CachedShift.self, CachedNews.self, CachedUser.self,
        CachedWorklog.self, CachedAngelTypeMembership.self, CachedLocation.self,
    ])
    let container = try ModelContainer(
        for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
    )
    return ModelContext(container)
}

extension StubbedNetworkTests {
    /// Drives `AppSyncCoordinator` through its failure, cancellation and notification
    /// branches — real (non-demo) instances go through `StubbedNetwork`, with a fake key store
    /// standing in for the Keychain.
    @Suite
    @MainActor
    struct AppSyncCoordinatorTests {
        private let keys = MemoryKeyStore()
        private let center = RecordingNotificationCenter()

        init() {
            StubbedNetwork.install()
            keys.keys["ref"] = "secret"
        }

        private func coordinator() -> AppSyncCoordinator {
            AppSyncCoordinator(
                credentialResolver: InstanceCredentialResolver(stores: [keys]),
                notificationScheduler: NotificationScheduler(center: center),
                newsNotifier: NewsNotifier(center: center)
            )
        }

        private func stubInstance() -> Instance {
            Instance(name: "Stub", baseURL: "https://stub.test", apiKeyKeychainRef: "ref")
        }

        private let prefix = "/api/v0-beta"

        @Test func everyDomainFailingMarksTheSyncAsFailedButStillReportsAllSteps() async throws {
            for path in ["/users/self/shifts", "/news", "/users/self", "/locations"] {
                StubURLProtocol.route("GET \(prefix)\(path)", status: 500)
            }
            let context = try makeContext()
            let instance = stubInstance()
            context.insert(instance)

            var steps = 0
            let succeeded = await coordinator().syncEverything(instances: [instance], in: context, onProgress: { _ in steps += 1 })
            #expect(!succeeded)
            #expect(steps == 5)
            #expect(center.added.isEmpty)
        }

        /// Reminders depend on the shift syncs only: a failing News/Profile/Locations step still schedules them.
        private func coordinator(capabilities: ServerCapabilities) -> AppSyncCoordinator {
            AppSyncCoordinator(
                newsSyncService: NewsSyncService(capabilities: capabilities),
                profileSyncService: ProfileSyncService(capabilities: capabilities),
                locationSyncService: LocationSyncService(capabilities: capabilities),
                credentialResolver: InstanceCredentialResolver(stores: [keys]),
                notificationScheduler: NotificationScheduler(center: center),
                newsNotifier: NewsNotifier(center: center),
                capabilities: capabilities
            )
        }

        private func freshCapabilities() -> ServerCapabilities {
            let name = "CoordinatorCapabilities-\(UUID().uuidString)"
            return ServerCapabilities(defaults: UserDefaults(suiteName: name)!)
        }

        /// ADR 0015: a 403/404 on an optional function is recorded as "not allowed"/"not offered" and
        /// the privileges of the profile decide the others.
        @Test func deniedFunctionsAreRecordedPerInstance() async throws {
            StubURLProtocol.route("GET \(prefix)/users/self/shifts", status: 403)
            StubURLProtocol.route("GET \(prefix)/news", status: 403)
            try StubURLProtocol.routeDemoOwnProfile("GET \(prefix)/users/self")
            StubURLProtocol.route("GET \(prefix)/users/self/worklogs", status: 403)
            StubURLProtocol.route("GET \(prefix)/users/self/angeltypes", status: 403)
            StubURLProtocol.route("GET \(prefix)/locations", status: 403)
            try StubURLProtocol.route("GET \(prefix)/messages", data: [Conversation]())
            let capabilities = freshCapabilities()
            let context = try makeContext()
            let instance = stubInstance()
            context.insert(instance)

            _ = await coordinator(capabilities: capabilities).syncEverything(instances: [instance], in: context)

            #expect(capabilities.status(.shifts, for: instance.id).state == .notAllowed)
            #expect(capabilities.status(.news, for: instance.id).state == .notAllowed)
            #expect(capabilities.status(.profileWorklogs, for: instance.id).state == .notAllowed)
            #expect(capabilities.status(.profileAngelTypes, for: instance.id).state == .notAllowed)
            #expect(capabilities.status(.locationsList, for: instance.id).state == .notAllowed)
            #expect(capabilities.status(.messages, for: instance.id).state == .available)
        }

        @Test func workingFunctionsAreRecordedAsAvailableAndOtherProfileErrorsStayFailures() async throws {
            try StubURLProtocol.route("GET \(prefix)/users/self/shifts", data: DemoData.shifts)
            try StubURLProtocol.route("GET \(prefix)/news", data: DemoData.news)
            try StubURLProtocol.routeDemoOwnProfile("GET \(prefix)/users/self")
            try StubURLProtocol.route("GET \(prefix)/users/self/worklogs", data: DemoData.worklogs)
            try StubURLProtocol.route("GET \(prefix)/users/self/angeltypes", data: DemoData.ownAngelTypes)
            try StubURLProtocol.route("GET \(prefix)/locations", data: DemoData.locations)
            try StubURLProtocol.route("GET \(prefix)/messages", data: await DemoData.conversations())
            let capabilities = freshCapabilities()
            let context = try makeContext()
            let instance = stubInstance()
            context.insert(instance)

            let succeeded = await coordinator(capabilities: capabilities).syncEverything(instances: [instance], in: context)
            #expect(succeeded)
            for feature in [ServerFeature.shifts, .news, .profileWorklogs, .profileAngelTypes, .locationsList, .messages] {
                #expect(capabilities.status(feature, for: instance.id).state == .available)
            }

            // A server error in the optional profile parts is still a real failure.
            StubURLProtocol.route("GET \(prefix)/users/self/worklogs", status: 500)
            #expect(await coordinator(capabilities: capabilities).syncEverything(instances: [instance], in: context) == false)
            try StubURLProtocol.route("GET \(prefix)/users/self/worklogs", data: DemoData.worklogs)
            StubURLProtocol.route("GET \(prefix)/users/self/angeltypes", status: 500)
            #expect(await coordinator(capabilities: capabilities).syncEverything(instances: [instance], in: context) == false)
        }

        @Test func shiftRemindersAreScheduledEvenWhenOtherDomainsFail() async throws {
            try StubURLProtocol.route("GET \(prefix)/users/self/shifts", data: DemoData.shifts)
            for path in ["/news", "/users/self", "/locations"] {
                StubURLProtocol.route("GET \(prefix)\(path)", status: 500)
            }
            let context = try makeContext()
            let instance = stubInstance()
            context.insert(instance)

            let succeeded = await coordinator().syncEverything(instances: [instance], in: context)
            #expect(!succeeded)
            #expect(!center.added.isEmpty)
        }

        /// Syncing just one instance (one switched on in Settings) must not cancel the others' reminders.
        @Test func syncingOneInstanceKeepsTheRemindersOfTheOthers() async throws {
            try StubURLProtocol.route("GET \(prefix)/users/self/shifts", data: DemoData.shifts)
            let context = try makeContext()
            let first = stubInstance()
            let second = stubInstance()
            context.insert(first)
            context.insert(second)
            let coordinator = coordinator()

            await coordinator.syncEverything(instances: [first, second], in: context, shiftsOnly: true)
            let both = center.added.count
            #expect(both > 0)

            await coordinator.syncEverything(
                instances: [first], in: context, shiftsOnly: true, reminderInstances: [first, second])
            #expect(center.added.count == both)

            // Without the hint only the synced instance's shifts are planned, as before.
            await coordinator.syncEverything(instances: [first], in: context, shiftsOnly: true)
            #expect(center.added.count < both)
        }

        private func routeAllDomains() throws {
            try StubURLProtocol.route("GET \(prefix)/users/self/shifts", data: DemoData.shifts)
            try StubURLProtocol.route("GET \(prefix)/news", data: DemoData.news)
            try StubURLProtocol.routeDemoOwnProfile("GET \(prefix)/users/self")
            try StubURLProtocol.route("GET \(prefix)/users/self/worklogs", data: DemoData.worklogs)
            try StubURLProtocol.route("GET \(prefix)/users/self/angeltypes", data: DemoData.ownAngelTypes)
            try StubURLProtocol.route("GET \(prefix)/locations", data: DemoData.locations)
            try StubURLProtocol.route("GET \(prefix)/messages", data: [Conversation]())
        }

        @Test func aRunReportsItsInstancesAndSteps() async throws {
            try routeAllDomains()
            let context = try makeContext()
            let instance = stubInstance()
            context.insert(instance)
            var events: [SyncEvent] = []

            let succeeded = await coordinator().syncEverything(
                instances: [instance], in: context, onEvent: { events.append($0) })
            #expect(succeeded)
            #expect(events.first == .planned([SyncPlannedInstance(id: instance.id, name: "Stub", totalSteps: 5)]))
            #expect(events.contains(.instanceStarted(id: instance.id)))
            #expect(events.contains(.stepStarted(id: instance.id, area: "Shifts")))
            #expect(events.contains(.stepStarted(id: instance.id, area: "Messages")))
            #expect(events.filter { if case .stepFinished = $0 { return true } else { return false } }.count == 5)
            #expect(events.last == .instanceFinished(id: instance.id, outcome: .succeeded))
        }

        @Test func anInstanceThatMakesNoProgressTimesOutAndTheNextOneStillRuns() async throws {
            let context = try makeContext()
            let slow = stubInstance()
            context.insert(slow)
            StubURLProtocol.route("GET \(prefix)/users/self/shifts", delay: 1.0)
            var events: [SyncEvent] = []
            var progress: [AppSyncCoordinator.Progress] = []

            let succeeded = await coordinator().syncEverything(
                instances: [slow], in: context, shiftsOnly: true, control: SyncControl(stepTimeout: 0.2),
                onEvent: { events.append($0) }, onProgress: { progress.append($0) })
            #expect(!succeeded)
            #expect(events.last == .instanceFinished(id: slow.id, outcome: .timedOut))
            #expect(progress.last?.completed == progress.last?.total)
            #expect(center.added.isEmpty) // no reminders from a sync that did not finish
        }

        @Test func aSkippedInstanceIsPassedOverAndTheOthersAreSynced() async throws {
            try routeAllDomains()
            let context = try makeContext()
            let first = stubInstance()
            let second = stubInstance()
            context.insert(first)
            context.insert(second)
            let control = SyncControl()
            control.skip(second.id)
            var events: [SyncEvent] = []

            let succeeded = await coordinator().syncEverything(
                instances: [first, second], in: context, shiftsOnly: true, control: control,
                onEvent: { events.append($0) })
            #expect(!succeeded)
            #expect(events.contains(.instanceFinished(id: first.id, outcome: .succeeded)))
            #expect(events.contains(.instanceFinished(id: second.id, outcome: .skipped)))
            #expect(!events.contains(.instanceStarted(id: second.id)))
        }

        @Test func skippingTheRunningInstanceStopsItsRemainingSteps() async throws {
            try routeAllDomains()
            let context = try makeContext()
            let instance = stubInstance()
            context.insert(instance)
            let control = SyncControl()
            var events: [SyncEvent] = []

            let succeeded = await coordinator().syncEverything(
                instances: [instance], in: context, control: control,
                onEvent: { event in
                    events.append(event)
                    if event == .stepFinished(id: instance.id, area: "Shifts") { control.skip(instance.id) }
                })
            #expect(!succeeded)
            #expect(events.last == .instanceFinished(id: instance.id, outcome: .skipped))
            #expect(!events.contains(.stepStarted(id: instance.id, area: "Messages")))
        }

        /// "Stop sync": cancelling the whole run while an instance is busy ends it without a failure.
        @Test func stoppingTheRunCancelsTheBusyInstanceWithoutCountingAFailure() async throws {
            try routeAllDomains()
            StubURLProtocol.route("GET \(prefix)/users/self/shifts", delay: 0.4)
            let context = try makeContext()
            let instance = stubInstance()
            context.insert(instance)
            let coordinator = coordinator()
            var events: [SyncEvent] = []

            let run = Task { @MainActor in
                await coordinator.syncEverything(instances: [instance], in: context, onEvent: { events.append($0) })
            }
            try await Task.sleep(for: .milliseconds(100))
            run.cancel()
            #expect(await run.value)
            #expect(!events.contains(.stepStarted(id: instance.id, area: "Messages")))
        }

        /// How many instances are inside a step at the same moment, read from the event stream.
        private func maxRunning(_ events: [SyncEvent]) -> Int {
            var running: Set<UUID> = []
            var peak = 0
            for event in events {
                switch event {
                case let .instanceStarted(id): running.insert(id)
                case let .instanceFinished(id, _): running.remove(id)
                default: break
                }
                peak = max(peak, running.count)
            }
            return peak
        }

        @Test func instancesRunAtTheSameTimeUnlessLimitedToOne() async throws {
            try routeAllDomains()
            StubURLProtocol.route("GET \(prefix)/users/self/shifts", delay: 0.05)
            let context = try makeContext()
            let instances = [stubInstance(), stubInstance(), stubInstance()]
            instances.forEach(context.insert)

            var parallel: [SyncEvent] = []
            #expect(await coordinator().syncEverything(
                instances: instances, in: context, shiftsOnly: true, maxConcurrentInstances: 0,
                onEvent: { parallel.append($0) }))
            #expect(maxRunning(parallel) == 3)

            var limited: [SyncEvent] = []
            #expect(await coordinator().syncEverything(
                instances: instances, in: context, shiftsOnly: true, maxConcurrentInstances: 2,
                onEvent: { limited.append($0) }))
            #expect(maxRunning(limited) == 2)

            var sequential: [SyncEvent] = []
            #expect(await coordinator().syncEverything(
                instances: instances, in: context, shiftsOnly: true, maxConcurrentInstances: 1,
                onEvent: { sequential.append($0) }))
            #expect(maxRunning(sequential) == 1)
            for id in instances.map(\.id) {
                #expect(sequential.contains(.instanceFinished(id: id, outcome: .succeeded)))
            }
        }

        /// Each running instance has its own no-progress timer: two hanging ones time out side by side.
        @Test func everyRunningInstanceHasItsOwnTimeout() async throws {
            let context = try makeContext()
            let first = stubInstance()
            let second = stubInstance()
            context.insert(first)
            context.insert(second)
            StubURLProtocol.route("GET \(prefix)/users/self/shifts", delay: 0.8)
            var events: [SyncEvent] = []
            var progress: [AppSyncCoordinator.Progress] = []

            let succeeded = await coordinator().syncEverything(
                instances: [first, second], in: context, shiftsOnly: true, control: SyncControl(stepTimeout: 0.2),
                maxConcurrentInstances: 0, onEvent: { events.append($0) }, onProgress: { progress.append($0) })
            #expect(!succeeded)
            #expect(events.contains(.instanceFinished(id: first.id, outcome: .timedOut)))
            #expect(events.contains(.instanceFinished(id: second.id, outcome: .timedOut)))
            #expect(maxRunning(events) == 2)
            #expect(progress.last?.completed == progress.last?.total)
        }

        @Test func aFailingInstanceIsReportedAsFailed() async throws {
            for path in ["/users/self/shifts", "/news", "/users/self", "/locations"] {
                StubURLProtocol.route("GET \(prefix)\(path)", status: 500)
            }
            let context = try makeContext()
            let instance = stubInstance()
            context.insert(instance)
            var events: [SyncEvent] = []

            _ = await coordinator().syncEverything(instances: [instance], in: context, onEvent: { events.append($0) })
            #expect(events.last == .instanceFinished(id: instance.id, outcome: .failed))
        }

        @Test func aCancelledSyncDoesNotCountAsAFailure() async throws {
            let context = try makeContext()
            let instance = stubInstance()
            context.insert(instance)
            let coordinator = coordinator()

            let task = Task { @MainActor in
                while !Task.isCancelled { await Task.yield() }
                return await coordinator.syncEverything(instances: [instance], in: context)
            }
            task.cancel()
            #expect(await task.value)
        }

        @Test func aSingleNewNewsPostIsAnnouncedWithItsInstanceName() async throws {
            try StubURLProtocol.route("GET \(prefix)/news", data: [DemoData.news[0]])
            try StubURLProtocol.route("GET \(prefix)/messages", data: [Conversation]())
            let context = try makeContext()
            let instance = stubInstance()
            context.insert(instance)

            _ = await coordinator().syncEverything(instances: [instance], in: context, notifyOnNewNews: true)

            #expect(center.added.count == 1)
            #expect(center.added[0].content.body.hasPrefix("Stub — "))
            #expect(instance.messagesSupported) // the probe flipped it from its default
        }

        @Test func severalNewPostsAreAnnouncedTogetherWithoutAnInstanceName() async throws {
            let context = try makeContext()
            let key = "ref"
            let store = MemoryKeyStore()
            store.keys[key] = "demo"
            let instance = Instance(name: "Demo", baseURL: Instance.demoBaseURL, apiKeyKeychainRef: key)
            context.insert(instance)
            let coordinator = AppSyncCoordinator(
                credentialResolver: InstanceCredentialResolver(stores: [store]),
                notificationScheduler: NotificationScheduler(center: center),
                newsNotifier: NewsNotifier(center: center)
            )

            let succeeded = await coordinator.syncEverything(instances: [instance], in: context, notifyOnNewNews: true)

            #expect(succeeded)
            #expect(center.added.contains { $0.content.title.hasSuffix("New Announcements") })
        }

        @Test func handleNotificationsFalseSkipsAllNotificationWork() async throws {
        let context = try makeContext()
        let instance = Instance(name: "Demo", baseURL: Instance.demoBaseURL, apiKeyKeychainRef: "ref")
        keys.keys["ref"] = "demo"
        context.insert(instance)

        _ = await coordinator().syncEverything(
            instances: [instance], in: context, notifyOnNewNews: true, handleNotifications: false
        )
        #expect(center.added.isEmpty)
    }

    @Test func nothingIsScheduledWhenNotificationsAreDenied() async throws {
            center.status = .denied
            let context = try makeContext()
            let instance = Instance(name: "Demo", baseURL: Instance.demoBaseURL, apiKeyKeychainRef: "ref")
            keys.keys["ref"] = "demo"
            context.insert(instance)

            _ = await coordinator().syncEverything(instances: [instance], in: context, notifyOnNewNews: true)
            #expect(center.added.isEmpty)
        }
    }
}

struct InstanceCredentialResolverTests {
    private let instance = Instance(name: "I", baseURL: "https://x.test/", apiKeyKeychainRef: "ref")

    @Test func theFirstStoreThatKnowsTheKeyWins() throws {
        let first = MemoryKeyStore(), second = MemoryKeyStore()
        first.keys["ref"] = "one"
        second.keys["ref"] = "two"
        let credential = try InstanceCredentialResolver(stores: [first, second]).credential(for: instance)
        #expect(credential.apiKey == "one")
        #expect(credential.baseURL == "https://x.test/api/v0-beta")
    }

    @Test func laterStoresAreTriedWhenEarlierOnesDoNotHaveTheKey() throws {
        let first = MemoryKeyStore(), second = MemoryKeyStore()
        second.keys["ref"] = "two"
        #expect(try InstanceCredentialResolver(stores: [first, second]).credential(for: instance).apiKey == "two")
    }

    @Test func aMissingKeyThrows() {
        #expect(throws: InstanceCredentialError.self) {
            try InstanceCredentialResolver(stores: [MemoryKeyStore()]).credential(for: instance)
        }
    }

    @Test func thePublicInitializerBuildsTheRealStores() {
        _ = InstanceCredentialResolver()
    }
}
