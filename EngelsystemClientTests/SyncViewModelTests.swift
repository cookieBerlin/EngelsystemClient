import Foundation
import SwiftData
import Testing
import EngelsystemClientKit
@testable import EngelsystemClient

/// Shared fixtures for the per-screen sync view models (Profile, Locations, News,
/// Location detail): all four follow the same shape — success, a missing credential,
/// a 401, a cancellation — so the scenarios are written once per view model against
/// the demo credential (success) and `StubbedNetwork` (401, cancellation).
@MainActor
private func makeContext() throws -> ModelContext {
    let schema = Schema([
        Instance.self, CachedShift.self, CachedNews.self, CachedUser.self, CachedWorklog.self,
        CachedAngelTypeMembership.self, CachedLocation.self,
    ])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    return ModelContext(try ModelContainer(for: schema, configurations: [config]))
}

private func seed(baseURL: String, in context: ModelContext, withKey: Bool = true) throws -> Instance {
    let ref = "sync-vm-tests-\(UUID().uuidString)"
    if withKey { try LocalKeychainStore().save(apiKey: "demo", for: ref) }
    let instance = Instance(name: "Test", baseURL: baseURL, apiKeyKeychainRef: ref)
    context.insert(instance)
    return instance
}

private func cleanUp(_ instance: Instance) {
    try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef)
}

extension StubbedNetworkTests {
    @Suite
    struct SyncViewModelTests {
        init() {
            StubbedNetwork.install()
        }

        private let stubBase = "https://stub.test"
        private let prefix = "/api/v0-beta"

        // MARK: Profile

        @Test @MainActor func profileRefreshSyncsTheDemoProfile() async throws {
            let context = try makeContext()
            let instance = try seed(baseURL: Instance.demoBaseURL, in: context)
            defer { cleanUp(instance) }
            let viewModel = ProfileViewModel()
            await viewModel.refresh(instances: [instance], in: context)
            #expect(viewModel.errorMessage == nil)
            #expect(!viewModel.isLoading)
            #expect(try context.fetch(FetchDescriptor<CachedUser>()).count == 1)
        }

        @Test @MainActor func profileRefreshReportsAMissingCredential() async throws {
            let context = try makeContext()
            let instance = try seed(baseURL: Instance.demoBaseURL, in: context, withKey: false)
            let viewModel = ProfileViewModel()
            await viewModel.refresh(instances: [instance], in: context)
            #expect(viewModel.errorMessage != nil)
            #expect(!viewModel.isUnauthorized)
        }

        @Test @MainActor func profileRefreshFlagsAnUnauthorizedServer() async throws {
            StubURLProtocol.route("GET \(prefix)/users/self", status: 401)
            let context = try makeContext()
            let instance = try seed(baseURL: stubBase, in: context)
            defer { cleanUp(instance) }
            let viewModel = ProfileViewModel()
            await viewModel.refresh(instances: [instance], in: context)
            #expect(viewModel.isUnauthorized)
            #expect(viewModel.errorMessage != nil)
        }

        @Test @MainActor func profileRefreshIgnoresCancellation() async throws {
            let context = try makeContext()
            let instance = try seed(baseURL: stubBase, in: context)
            defer { cleanUp(instance) }
            let viewModel = ProfileViewModel()
            let task = Task { @MainActor in
                while !Task.isCancelled { await Task.yield() }
                await viewModel.refresh(instances: [instance], in: context)
            }
            task.cancel()
            await task.value
            #expect(viewModel.errorMessage == nil)
        }

        // MARK: Locations

        @Test @MainActor func locationsRefreshSyncsTheDemoLocations() async throws {
            let context = try makeContext()
            let instance = try seed(baseURL: Instance.demoBaseURL, in: context)
            defer { cleanUp(instance) }
            let viewModel = LocationsViewModel()
            await viewModel.refresh(instances: [instance], in: context)
            #expect(viewModel.errorMessage == nil)
            #expect(try context.fetch(FetchDescriptor<CachedLocation>()).count == 4)
        }

        @Test @MainActor func locationsRefreshReportsMissingCredentialUnauthorizedAndIgnoresCancellation() async throws {
            let context = try makeContext()
            let missing = try seed(baseURL: Instance.demoBaseURL, in: context, withKey: false)
            let viewModel = LocationsViewModel()
            await viewModel.refresh(instances: [missing], in: context)
            #expect(viewModel.errorMessage != nil)

            StubURLProtocol.route("GET \(prefix)/locations", status: 401)
            let stub = try seed(baseURL: stubBase, in: context)
            defer { cleanUp(stub) }
            await viewModel.refresh(instances: [stub], in: context)
            #expect(viewModel.isUnauthorized)

            let task = Task { @MainActor in
                while !Task.isCancelled { await Task.yield() }
                await viewModel.refresh(instances: [stub], in: context)
            }
            task.cancel()
            await task.value
            #expect(viewModel.errorMessage == nil)
        }

        // MARK: News

        @Test @MainActor func newsRefreshSyncsTheDemoNews() async throws {
            let context = try makeContext()
            let instance = try seed(baseURL: Instance.demoBaseURL, in: context)
            defer { cleanUp(instance) }
            let viewModel = NewsViewModel()
            await viewModel.refresh(instances: [instance], in: context)
            #expect(viewModel.errorMessage == nil)
            #expect(try context.fetch(FetchDescriptor<CachedNews>()).count == 5)
        }

        @Test @MainActor func newsRefreshReportsMissingCredentialUnauthorizedAndIgnoresCancellation() async throws {
            let context = try makeContext()
            let missing = try seed(baseURL: Instance.demoBaseURL, in: context, withKey: false)
            let viewModel = NewsViewModel()
            await viewModel.refresh(instances: [missing], in: context)
            #expect(viewModel.errorMessage != nil)

            StubURLProtocol.route("GET \(prefix)/news", status: 401)
            let stub = try seed(baseURL: stubBase, in: context)
            defer { cleanUp(stub) }
            await viewModel.refresh(instances: [stub], in: context)
            #expect(viewModel.isUnauthorized)

            let task = Task { @MainActor in
                while !Task.isCancelled { await Task.yield() }
                await viewModel.refresh(instances: [stub], in: context)
            }
            task.cancel()
            await task.value
            #expect(viewModel.errorMessage == nil)
        }

        // MARK: Location detail

        @Test @MainActor func locationDetailRefreshUpdatesTheCachedRow() async throws {
            let context = try makeContext()
            let instance = try seed(baseURL: Instance.demoBaseURL, in: context)
            defer { cleanUp(instance) }
            let cached = CachedLocation(
                serverID: 1, instanceID: instance.id, name: "Stale", locationDescription: "", url: "u"
            )
            context.insert(cached)
            let viewModel = LocationDetailViewModel()
            await viewModel.refresh(location: cached, instance: instance, in: context)
            #expect(viewModel.errorMessage == nil)
            #expect(cached.name != "Stale")
        }

        /// COMPAT(#1711): a 404 from `GET /locations/{id}` keeps the cached data and shows no error.
        @Test @MainActor func locationDetailRefreshWithoutServerSupportIsSilent() async throws {
            let context = try makeContext()
            let instance = try seed(baseURL: Instance.demoBaseURL, in: context)
            defer { cleanUp(instance) }
            let cached = CachedLocation(serverID: 999, instanceID: instance.id, name: "Cached", locationDescription: "", url: "u")
            context.insert(cached)
            let viewModel = LocationDetailViewModel()
            await viewModel.refresh(location: cached, instance: instance, in: context)
            #expect(viewModel.errorMessage == nil)
            #expect(viewModel.refreshUnavailable)
            #expect(cached.name == "Cached")

            let known = CachedLocation(serverID: 1, instanceID: instance.id, name: "Stale", locationDescription: "", url: "u")
            context.insert(known)
            await viewModel.refresh(location: known, instance: instance, in: context)
            #expect(!viewModel.refreshUnavailable)
        }

        @Test @MainActor func shiftDetailRefreshUpdatesTheCachedShiftAndStaysSilentWithoutServerSupport() async throws {
            let context = try makeContext()
            let instance = try seed(baseURL: Instance.demoBaseURL, in: context)
            defer { cleanUp(instance) }
            let cached = CachedShift(
                serverID: 1, instanceID: instance.id, title: "Stale", startsAt: Date(), endsAt: Date(),
                locationID: 1, shiftTypeID: 1, url: "u")
            context.insert(cached)
            let viewModel = ShiftDetailViewModel()
            await viewModel.refresh(shift: cached, instance: instance, in: context)
            #expect(viewModel.errorMessage == nil)
            #expect(!viewModel.refreshUnavailable)
            #expect(cached.title != "Stale")

            // COMPAT(#1724): an unknown id (404) keeps the cached data and shows no error.
            let unknown = CachedShift(
                serverID: 999, instanceID: instance.id, title: "Cached", startsAt: Date(), endsAt: Date(),
                locationID: 1, shiftTypeID: 1, url: "u")
            context.insert(unknown)
            await viewModel.refresh(shift: unknown, instance: instance, in: context)
            #expect(viewModel.errorMessage == nil)
            #expect(viewModel.refreshUnavailable)
            #expect(unknown.title == "Cached")
        }

        @Test @MainActor func shiftDetailRefreshReportsFailuresButIgnoresCancellation() async throws {
            let context = try makeContext()
            let missing = try seed(baseURL: Instance.demoBaseURL, in: context, withKey: false)
            let cached = CachedShift(
                serverID: 1, instanceID: missing.id, title: "S", startsAt: Date(), endsAt: Date(),
                locationID: 1, shiftTypeID: 1, url: "u")
            let viewModel = ShiftDetailViewModel()
            await viewModel.refresh(shift: cached, instance: missing, in: context)
            #expect(viewModel.errorMessage != nil)

            let stub = try seed(baseURL: stubBase, in: context)
            defer { cleanUp(stub) }
            let task = Task { @MainActor in
                while !Task.isCancelled { await Task.yield() }
                await viewModel.refresh(shift: cached, instance: stub, in: context)
            }
            task.cancel()
            await task.value
            #expect(viewModel.errorMessage == nil)
        }

        @Test @MainActor func locationDetailRefreshReportsFailuresButIgnoresCancellation() async throws {
            let context = try makeContext()
            let missing = try seed(baseURL: Instance.demoBaseURL, in: context, withKey: false)
            let cached = CachedLocation(serverID: 1, instanceID: missing.id, name: "L", locationDescription: "", url: "u")
            let viewModel = LocationDetailViewModel()
            await viewModel.refresh(location: cached, instance: missing, in: context)
            #expect(viewModel.errorMessage != nil)

            let stub = try seed(baseURL: stubBase, in: context)
            defer { cleanUp(stub) }
            let task = Task { @MainActor in
                while !Task.isCancelled { await Task.yield() }
                await viewModel.refresh(location: cached, instance: stub, in: context)
            }
            task.cancel()
            await task.value
            #expect(viewModel.errorMessage == nil)
        }
    }
}
