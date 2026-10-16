import Foundation
import SwiftData
import Testing
@testable import EngelsystemClientKit

@MainActor
private func freshDefaults() -> UserDefaults {
    let name = "ServerCapabilitiesTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@MainActor
private func makeContext() throws -> ModelContext {
    let schema = Schema([Instance.self, CachedNews.self, CachedLocation.self])
    let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    return ModelContext(container)
}

private func newsItem(commentsCount: Int?) -> News {
    News(id: 1, name: "n", text: "t", isMeeting: false, isPinned: false, isHighlighted: false,
         createdAt: Date(), updatedAt: nil, url: "https://example.org/news/1", commentsCount: commentsCount)
}

@Suite @MainActor
struct ServerCapabilitiesStoreTests {
    @Test func unknownFeaturesAreAvailable() {
        let capabilities = ServerCapabilities(defaults: freshDefaults())
        for feature in ServerFeature.allCases {
            #expect(capabilities.isAvailable(feature, for: UUID()))
        }
    }

    @Test func theDemoInstanceHasEveryListedFunction() {
        let capabilities = ServerCapabilities(defaults: freshDefaults())
        let id = UUID()
        capabilities.recordDemoInstance(id)
        #expect(capabilities.summary(for: id) == (ServerFeature.listed.count, ServerFeature.listed.count))
    }

    @Test func recordedValuesAreRememberedPerInstanceAndFeature() {
        let capabilities = ServerCapabilities(defaults: freshDefaults())
        let a = UUID(), b = UUID()
        capabilities.record(.newsComments, supported: false, for: a)
        #expect(!capabilities.isAvailable(.newsComments, for: a))
        #expect(capabilities.isAvailable(.newsComments, for: b))
        #expect(capabilities.isAvailable(.locationsList, for: a))
        capabilities.record(.newsComments, supported: true, for: a)
        #expect(capabilities.isAvailable(.newsComments, for: a))
    }

    @Test func nilLeavesPreviousKnowledgeUntouched() {
        let capabilities = ServerCapabilities(defaults: freshDefaults())
        let id = UUID()
        capabilities.record(.locationDetail, supported: false, for: id)
        capabilities.record(.locationDetail, supported: nil, for: id)
        #expect(!capabilities.isAvailable(.locationDetail, for: id))
    }

    @Test func valuesSurviveARecreatedStore() {
        let defaults = freshDefaults()
        let id = UUID()
        ServerCapabilities(defaults: defaults).record(.locationsList, supported: false, for: id)
        #expect(!ServerCapabilities(defaults: defaults).isAvailable(.locationsList, for: id))
    }

    @Test func availabilityForAnyOfSeveralInstances() {
        let capabilities = ServerCapabilities(defaults: freshDefaults())
        let a = UUID(), b = UUID()
        capabilities.record(.locationsList, supported: false, for: a)
        #expect(capabilities.isAvailable(.locationsList, forAnyOf: [a, b]))
        capabilities.record(.locationsList, supported: false, for: b)
        #expect(!capabilities.isAvailable(.locationsList, forAnyOf: [a, b]))
        #expect(!capabilities.isAvailable(.locationsList, forAnyOf: []))
    }

    @Test func newsCommentsAreSupportedWhenAnyItemCarriesACount() {
        #expect(ServerCapabilities.newsCommentsSupported(by: []) == nil)
        #expect(ServerCapabilities.newsCommentsSupported(by: [newsItem(commentsCount: nil)]) == false)
        #expect(ServerCapabilities.newsCommentsSupported(by: [newsItem(commentsCount: nil), newsItem(commentsCount: 0)]) == true)
    }

    @Test func everyFeatureHasATitleAndTheRightPrivilege() {
        #expect(Set(ServerFeature.allCases.map(\.title)).count == ServerFeature.allCases.count)
        #expect(ServerFeature.news.requiredPrivilege == "news")
        #expect(ServerFeature.locationDetail.requiredPrivilege == "locations.view")
        #expect(ServerFeature.messages.requiredPrivilege == "user_messages")
        #expect(ServerFeature.signOutDeadline.requiredPrivilege == "user_shifts")
        #expect(ServerFeature.shifts.requiredPrivilege == nil)
    }

    @Test func statusDefaultsToUnknownAndKeepsStateEvidenceAndTime() {
        let capabilities = ServerCapabilities(defaults: freshDefaults())
        let id = UUID()
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(capabilities.status(.news, for: id) == .unknown)
        capabilities.record(.news, state: .notAllowed, evidence: .privileges, privilege: "news", for: id, now: now)
        #expect(capabilities.status(.news, for: id)
            == FeatureStatus(state: .notAllowed, evidence: .privileges, privilege: "news", checkedAt: now))
        #expect(!capabilities.isAvailable(.news, for: id))
        capabilities.record(.news, state: .unknown, evidence: .probe, for: id)
        #expect(capabilities.status(.news, for: id).state == .notAllowed)
    }

    @Test func failuresMapTo403NotAllowedAnd404NotOffered() {
        let capabilities = ServerCapabilities(defaults: freshDefaults())
        let id = UUID()
        #expect(capabilities.record(.locationsList, afterFailure: .forbidden, for: id))
        #expect(capabilities.status(.locationsList, for: id).state == .notAllowed)
        #expect(capabilities.status(.locationsList, for: id).privilege == "locations.view")
        #expect(capabilities.status(.locationsList, for: id).evidence == .forbidden)
        #expect(capabilities.record(.newsComments, afterFailure: .notFound, for: id))
        #expect(capabilities.status(.newsComments, for: id).state == .notOffered)
        #expect(capabilities.status(.newsComments, for: id).evidence == .notFound)
        #expect(!capabilities.record(.shifts, afterFailure: .unauthorized, for: id))
        #expect(capabilities.status(.shifts, for: id) == .unknown)
    }

    @Test func privilegesDecideTheFunctionsThatNeedOne() {
        let capabilities = ServerCapabilities(defaults: freshDefaults())
        let id = UUID()
        capabilities.applyPrivileges(nil, for: id)
        #expect(capabilities.status(.news, for: id) == .unknown)

        capabilities.applyPrivileges(["news", "user_messages"], for: id)
        #expect(capabilities.status(.news, for: id).state == .available)
        #expect(capabilities.status(.news, for: id).evidence == .privileges)
        #expect(capabilities.status(.messages, for: id).state == .available)
        #expect(capabilities.status(.locationsList, for: id).state == .notAllowed)
        #expect(capabilities.status(.locationsList, for: id).privilege == "locations.view")
        #expect(capabilities.status(.shiftTeam, for: id).privilege == "user_shifts")
        // Functions without a required privilege are not touched.
        #expect(capabilities.status(.shifts, for: id) == .unknown)

        // The read-only `api` privilege grants every GET.
        capabilities.applyPrivileges(["api"], for: id)
        for feature in ServerFeature.allCases where feature.requiredPrivilege != nil {
            #expect(capabilities.status(feature, for: id).state == .available)
        }
    }

    @Test func statusSurvivesARecreatedStoreAndMigratesTheLegacyFormat() {
        let defaults = freshDefaults()
        let id = UUID()
        ServerCapabilities(defaults: defaults).record(.messages, state: .notOffered, evidence: .notFound, for: id)
        #expect(ServerCapabilities(defaults: defaults).status(.messages, for: id).state == .notOffered)
        #expect(ServerCapabilities(defaults: defaults).status(.messages, for: id).evidence == .notFound)

        let legacy = freshDefaults()
        legacy.set([id.uuidString + "/locationsList": false, id.uuidString + "/newsComments": true],
                   forKey: ServerCapabilities.legacyDefaultsKey)
        let migrated = ServerCapabilities(defaults: legacy)
        #expect(migrated.status(.locationsList, for: id).state == .notOffered)
        #expect(migrated.status(.newsComments, for: id).state == .available)
    }

    @Test func summaryCountsTheAvailableFunctions() {
        let capabilities = ServerCapabilities(defaults: freshDefaults())
        let id = UUID()
        #expect(capabilities.summary(for: id) == (0, ServerFeature.listed.count))
        capabilities.record(.news, state: .available, evidence: .probe, for: id)
        capabilities.record(.messages, state: .notOffered, evidence: .notFound, for: id)
        #expect(capabilities.summary(for: id).available == 1)
    }

    @Test func featureSummaryFollowsThePrivileges() {
        #expect(ServerCapabilities.featureSummary(privileges: nil) == nil)
        let total = ServerFeature.listed.count
        #expect(ServerCapabilities.featureSummary(privileges: ["api"]) == "\(total) of \(total) features available")
        let withoutAny = ServerCapabilities.featureSummary(privileges: [])
        let free = ServerFeature.listed.filter { $0.requiredPrivilege == nil }.count
        #expect(withoutAny == "\(free) of \(total) features available")
        #expect(ServerCapabilities.summaryText(available: 1, total: 2) == "1 of 2 features available")
    }

    @Test func afterErrorOnlyRecordsAPIErrors() {
        let capabilities = ServerCapabilities(defaults: freshDefaults())
        let id = UUID()
        struct Other: Error {}
        #expect(!capabilities.record(.news, afterError: Other(), for: id))
        #expect(capabilities.record(.news, afterError: APIError.forbidden, for: id))
        #expect(capabilities.status(.news, for: id).state == .notAllowed)
    }

    @Test func sharedInstanceExists() {
        #expect(ServerCapabilities.shared.isAvailable(.newsComments, for: UUID()))
    }
}

extension StubbedNetworkTests {
    @Suite @MainActor
    struct ServerCapabilitySyncTests {
        init() { StubbedNetwork.install() }

        @Test func newsSyncRecordsWhetherCommentsAreSupported() async throws {
            let capabilities = ServerCapabilities(defaults: freshDefaults())
            let context = try makeContext()
            let instance = Instance(name: "I", baseURL: "https://stub.test", apiKeyKeychainRef: "r")
            let service = NewsSyncService(apiClient: APIClient(), capabilities: capabilities)
            let json = """
            {"data":[{"id":1,"name":"Hello","text":"Body","is_meeting":false,"is_pinned":false,\
            "is_highlighted":false,"created_at":"2026-10-01T10:00:00+00:00","updated_at":null,\
            "url":"https://example.org/news/1"}]}
            """
            StubURLProtocol.route("GET /news", body: Data(json.utf8))
            try await service.sync(instance: instance, credential: StubbedNetwork.credential, in: context)
            #expect(!capabilities.isAvailable(.newsComments, for: instance.id))

            try StubURLProtocol.route("GET /news", data: DemoData.news)
            try await service.sync(instance: instance, credential: StubbedNetwork.credential, in: context)
            #expect(capabilities.isAvailable(.newsComments, for: instance.id))
        }

        @Test func locationListForbiddenHidesLocationsInsteadOfFailing() async throws {
            let capabilities = ServerCapabilities(defaults: freshDefaults())
            let context = try makeContext()
            let instance = Instance(name: "I", baseURL: "https://stub.test", apiKeyKeychainRef: "r")
            let service = LocationSyncService(apiClient: APIClient(), capabilities: capabilities)
            StubURLProtocol.route("GET /locations", status: 403)
            let result = try await service.sync(instance: instance, credential: StubbedNetwork.credential, in: context)
            #expect(result.isEmpty)
            #expect(!capabilities.isAvailable(.locationsList, for: instance.id))

            try StubURLProtocol.route("GET /locations", data: DemoData.locations)
            let loaded = try await service.sync(instance: instance, credential: StubbedNetwork.credential, in: context)
            #expect(loaded.count == DemoData.locations.count)
            #expect(capabilities.isAvailable(.locationsList, for: instance.id))
        }

        @Test func locationListOtherErrorsStillThrow() async throws {
            let capabilities = ServerCapabilities(defaults: freshDefaults())
            let instance = Instance(name: "I", baseURL: "https://stub.test", apiKeyKeychainRef: "r")
            let service = LocationSyncService(apiClient: APIClient(), capabilities: capabilities)
            StubURLProtocol.route("GET /locations", status: 500)
            await #expect(throws: APIError.server(statusCode: 500)) {
                try await service.sync(instance: instance, credential: StubbedNetwork.credential, in: try makeContext())
            }
            #expect(capabilities.isAvailable(.locationsList, for: instance.id))
        }

        @Test func locationDetailRecordsSupportAndLackOfIt() async throws {
            let capabilities = ServerCapabilities(defaults: freshDefaults())
            let context = try makeContext()
            let instance = Instance(name: "I", baseURL: "https://stub.test", apiKeyKeychainRef: "r")
            let service = LocationSyncService(apiClient: APIClient(), capabilities: capabilities)
            let location = DemoData.locations[0]

            StubURLProtocol.route("GET /locations/\(location.id)", status: 404)
            await #expect(throws: APIError.notFound) {
                try await service.refreshOne(serverID: location.id, instance: instance, credential: StubbedNetwork.credential, in: context)
            }
            #expect(!capabilities.isAvailable(.locationDetail, for: instance.id))

            StubURLProtocol.route("GET /locations/\(location.id)", status: 403)
            await #expect(throws: APIError.forbidden) {
                try await service.refreshOne(serverID: location.id, instance: instance, credential: StubbedNetwork.credential, in: context)
            }

            try StubURLProtocol.route("GET /locations/\(location.id)", data: location)
            try await service.refreshOne(serverID: location.id, instance: instance, credential: StubbedNetwork.credential, in: context)
            #expect(capabilities.isAvailable(.locationDetail, for: instance.id))
        }

        @Test func singleShiftRefreshRecordsSupportAndLackOfIt() async throws {
            let capabilities = ServerCapabilities(defaults: freshDefaults())
            let context = try makeContext()
            let instance = Instance(name: "I", baseURL: "https://stub.test", apiKeyKeychainRef: "r")
            let service = ShiftSyncService(apiClient: APIClient(), capabilities: capabilities)
            let shift = DemoData.shifts[0]

            StubURLProtocol.route("GET /shifts/\(shift.id)", status: 404)
            await #expect(throws: APIError.notFound) {
                try await service.refreshOne(serverID: shift.id, instance: instance, credential: StubbedNetwork.credential, in: context)
            }
            #expect(capabilities.status(.singleShiftRefresh, for: instance.id).state == .notOffered)

            StubURLProtocol.route("GET /shifts/\(shift.id)", status: 403)
            await #expect(throws: APIError.forbidden) {
                try await service.refreshOne(serverID: shift.id, instance: instance, credential: StubbedNetwork.credential, in: context)
            }
            #expect(capabilities.status(.singleShiftRefresh, for: instance.id).state == .notAllowed)

            try StubURLProtocol.route("GET /shifts/\(shift.id)", data: shift)
            let cached = try await service.refreshOne(
                serverID: shift.id, instance: instance, credential: StubbedNetwork.credential, in: context)
            #expect(cached.serverID == shift.id)
            #expect(capabilities.status(.singleShiftRefresh, for: instance.id).state == .available)

            StubURLProtocol.route("GET /shifts/\(shift.id)", body: Data("{}".utf8))
            await #expect(throws: APIError.decoding("Missing data in /shifts/{id} response")) {
                try await APIClient().fetchShift(id: shift.id, StubbedNetwork.credential)
            }
        }
    }
}
