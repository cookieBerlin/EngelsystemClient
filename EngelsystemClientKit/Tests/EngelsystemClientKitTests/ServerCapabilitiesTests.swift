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
    }
}
