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
