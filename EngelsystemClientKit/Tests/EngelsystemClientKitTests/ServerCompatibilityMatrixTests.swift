import Foundation
import SwiftData
import Testing
@testable import EngelsystemClientKit

private final class MatrixKeyStore: APIKeyStore, @unchecked Sendable {
    struct Missing: Error {}
    func save(apiKey: String, for reference: String) throws {}
    func loadAPIKey(for reference: String) throws -> String { "secret" }
    func deleteAPIKey(for reference: String) throws {}
}

extension StubbedNetworkTests {
    /// The compatibility matrix (ADR 0015, backlog K-13): one server per vintage — upstream today, each
    /// PR alone, the stacked shift chain, all PRs — and per function the state the app must end up
    /// with. A function that is missing or not allowed is hidden silently: the sync still succeeds.
    @Suite
    @MainActor
    struct ServerCompatibilityMatrixTests {
        init() { StubbedNetwork.install() }

        /// Runs a full sync against `fixture` and returns the recorded states plus the sync result.
        private func sync(_ fixture: ServerFixture) async throws -> (states: [ServerFeature: FeatureState], succeeded: Bool) {
            StubbedNetwork.install()
            try fixture.install()
            let schema = Schema([
                Instance.self, NotificationLeadTimeSettings.self, CachedShift.self, CachedNews.self, CachedUser.self,
                CachedWorklog.self, CachedAngelTypeMembership.self, CachedLocation.self,
            ])
            let container = try ModelContainer(
                for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
            let context = ModelContext(container)
            let instance = Instance(name: "Stub", baseURL: "https://stub.test", apiKeyKeychainRef: "ref")
            context.insert(instance)
            let capabilities = ServerCapabilities(defaults: UserDefaults(suiteName: "Matrix-\(UUID().uuidString)")!)
            let center = RecordingNotificationCenter()
            let coordinator = AppSyncCoordinator(
                newsSyncService: NewsSyncService(capabilities: capabilities),
                profileSyncService: ProfileSyncService(capabilities: capabilities),
                locationSyncService: LocationSyncService(capabilities: capabilities),
                credentialResolver: InstanceCredentialResolver(stores: [MatrixKeyStore()]),
                notificationScheduler: NotificationScheduler(center: center),
                newsNotifier: NewsNotifier(center: center),
                capabilities: capabilities
            )
            let succeeded = await coordinator.syncEverything(instances: [instance], in: context)
            var states: [ServerFeature: FeatureState] = [:]
            for feature in ServerFeature.allCases { states[feature] = capabilities.status(feature, for: instance.id).state }
            return (states, succeeded)
        }

        private func expect(
            _ fixture: ServerFixture, _ expected: [ServerFeature: FeatureState], succeeds: Bool = true,
            sourceLocation: SourceLocation = #_sourceLocation
        ) async throws {
            let result = try await sync(fixture)
            #expect(result.succeeded == succeeds, "\(fixture.name): sync result", sourceLocation: sourceLocation)
            for (feature, state) in expected {
                #expect(result.states[feature] == state, "\(fixture.name): \(feature.rawValue)", sourceLocation: sourceLocation)
            }
        }

        @Test func upstreamTodayOffersTheBasicsAndHidesTheRest() async throws {
            try await expect(.upstreamToday, [
                .shifts: .available, .news: .available, .newsComments: .notOffered, .locationsList: .available,
                .messages: .notOffered, .profileWorklogs: .available, .profileAngelTypes: .available,
                .locationDetail: .unknown, .shiftTypeDescription: .unknown,
            ])
        }

        @Test func eachPRAddsExactlyItsOwnFunction() async throws {
            try await expect(.with(pr: 1710), [.newsComments: .available, .messages: .notOffered])
            try await expect(.with(pr: 1720), [.messages: .available, .newsComments: .notOffered])
            try await expect(.with(pr: 1711), [.locationsList: .available, .messages: .notOffered])
        }

        @Test func privilegesDecideWhatTheAccountMayUse() async throws {
            let noRights = ServerFixture.allPRs.account(privileges: [])
            try await expect(noRights, [
                .news: .notAllowed, .locationsList: .notAllowed, .locationDetail: .notAllowed, .messages: .notAllowed,
                .shifts: .available, .profileWorklogs: .available,
            ], succeeds: true)

            let newsOnly = ServerFixture.allPRs.account(privileges: ["news"])
            try await expect(newsOnly, [
                .news: .available, .newsComments: .available, .locationsList: .notAllowed, .messages: .notAllowed,
            ])

            try await expect(.allPRs, [
                .news: .available, .newsComments: .available, .locationsList: .available, .locationDetail: .available,
                .messages: .available,
            ])
        }

        @Test func theShiftChainAddsNothingTheSyncHasToHide() async throws {
            try await expect(.shiftChain, [.shifts: .available, .news: .available, .messages: .notOffered])
        }

        @Test func aServerWithoutAPrivilegesFieldIsNeverCalledForbiddenByGuessing() async throws {
            let result = try await sync(.upstreamToday)
            #expect(result.states[.locationDetail] == .unknown)
            #expect(result.states[.messages] == .notOffered)
        }
    }
}
