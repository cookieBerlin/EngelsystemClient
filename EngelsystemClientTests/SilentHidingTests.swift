import Foundation
import SwiftData
import Testing
import EngelsystemClientKit
@testable import EngelsystemClient

@MainActor
private func makeContext() throws -> ModelContext {
    let schema = Schema([
        Instance.self, CachedShift.self, CachedNews.self, CachedUser.self, CachedWorklog.self,
        CachedAngelTypeMembership.self, CachedLocation.self,
    ])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    return ModelContext(try ModelContainer(for: schema, configurations: [config]))
}

@MainActor
private func freshCapabilities() -> ServerCapabilities {
    ServerCapabilities(defaults: UserDefaults(suiteName: "SilentHiding-\(UUID().uuidString)")!)
}

@MainActor
private func seed(in context: ModelContext) throws -> Instance {
    let ref = "silent-hiding-\(UUID().uuidString)"
    try LocalKeychainStore().save(apiKey: "key", for: ref)
    let instance = Instance(name: "Stub", baseURL: "https://stub.test", apiKeyKeychainRef: ref)
    context.insert(instance)
    return instance
}

extension StubbedNetworkTests {
    /// ADR 0015: a 403/404 on an optional function hides it silently (no banner) and is recorded for the
    /// instance's Features list; real errors (here 500) still show.
    @Suite
    struct SilentHidingTests {
        init() { StubbedNetwork.install() }

        private let prefix = "/api/v0-beta"

        @Test @MainActor func deniedShiftsAreHiddenSilentlyAndServerErrorsStillShow() async throws {
            let context = try makeContext()
            let instance = try seed(in: context)
            defer { try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef) }
            let capabilities = freshCapabilities()
            let viewModel = ShiftsViewModel(capabilities: capabilities)

            StubURLProtocol.route("GET \(prefix)/users/self/shifts", status: 403)
            await viewModel.refresh(instances: [instance], in: context, handleNotifications: false)
            #expect(viewModel.errorMessage == nil)
            #expect(capabilities.status(.shifts, for: instance.id).state == .notAllowed)

            StubURLProtocol.route("GET \(prefix)/users/self/shifts", status: 500)
            await viewModel.refresh(instances: [instance], in: context, handleNotifications: false)
            #expect(viewModel.errorMessage != nil)

            try StubURLProtocol.route("GET \(prefix)/users/self/shifts", data: [Shift]())
            await viewModel.refresh(instances: [instance], in: context, handleNotifications: false)
            #expect(viewModel.errorMessage == nil)
            #expect(capabilities.status(.shifts, for: instance.id).state == .available)
        }

        @Test @MainActor func deniedNewsIsHiddenSilentlyAndServerErrorsStillShow() async throws {
            let context = try makeContext()
            let instance = try seed(in: context)
            defer { try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef) }
            let capabilities = freshCapabilities()
            let viewModel = NewsViewModel(capabilities: capabilities)

            StubURLProtocol.route("GET \(prefix)/news", status: 403)
            await viewModel.refresh(instances: [instance], in: context)
            #expect(viewModel.errorMessage == nil)
            #expect(capabilities.status(.news, for: instance.id).state == .notAllowed)

            StubURLProtocol.route("GET \(prefix)/news", status: 500)
            await viewModel.refresh(instances: [instance], in: context)
            #expect(viewModel.errorMessage != nil)

            try StubURLProtocol.route("GET \(prefix)/news", data: [News]())
            await viewModel.refresh(instances: [instance], in: context)
            #expect(viewModel.errorMessage == nil)
            #expect(capabilities.status(.news, for: instance.id).state == .available)
        }

        @Test @MainActor func deniedProfilePartsAreHiddenSilentlyButServerErrorsStillShow() async throws {
            let context = try makeContext()
            let instance = try seed(in: context)
            defer { try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef) }
            let capabilities = freshCapabilities()
            let viewModel = ProfileViewModel(
                syncService: ProfileSyncService(capabilities: capabilities), capabilities: capabilities)
            try StubURLProtocol.routeDemoOwnProfile("GET \(prefix)/users/self")

            StubURLProtocol.route("GET \(prefix)/users/self/worklogs", status: 403)
            StubURLProtocol.route("GET \(prefix)/users/self/angeltypes", status: 403)
            await viewModel.refresh(instances: [instance], in: context)
            #expect(viewModel.errorMessage == nil)
            #expect(capabilities.status(.profileWorklogs, for: instance.id).state == .notAllowed)
            #expect(capabilities.status(.profileAngelTypes, for: instance.id).state == .notAllowed)

            StubURLProtocol.route("GET \(prefix)/users/self/worklogs", status: 500)
            await viewModel.refresh(instances: [instance], in: context)
            #expect(viewModel.errorMessage != nil)

            try StubURLProtocol.route("GET \(prefix)/users/self/worklogs", data: [Worklog]())
            StubURLProtocol.route("GET \(prefix)/users/self/angeltypes", status: 500)
            await viewModel.refresh(instances: [instance], in: context)
            #expect(viewModel.errorMessage != nil)

            try StubURLProtocol.route("GET \(prefix)/users/self/angeltypes", data: [UserAngelType]())
            await viewModel.refresh(instances: [instance], in: context)
            #expect(viewModel.errorMessage == nil)
            #expect(capabilities.status(.profileWorklogs, for: instance.id).state == .available)
            #expect(capabilities.status(.profileAngelTypes, for: instance.id).state == .available)
        }

        @Test @MainActor func deniedMessagesAreHiddenSilentlyAndServerErrorsStillShow() async throws {
            let context = try makeContext()
            let instance = try seed(in: context)
            defer { try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef) }
            let capabilities = freshCapabilities()
            let viewModel = MessagesViewModel(capabilities: capabilities)

            StubURLProtocol.route("GET \(prefix)/messages", status: 403)
            await viewModel.refresh(instances: [instance])
            #expect(viewModel.errorMessage == nil)
            #expect(capabilities.status(.messages, for: instance.id).state == .notAllowed)

            StubURLProtocol.route("GET \(prefix)/messages", status: 500)
            await viewModel.refresh(instances: [instance])
            #expect(viewModel.errorMessage != nil)

            try StubURLProtocol.route("GET \(prefix)/messages", data: [Conversation]())
            await viewModel.refresh(instances: [instance])
            #expect(viewModel.errorMessage == nil)
            #expect(capabilities.status(.messages, for: instance.id).state == .available)
        }
    }
}
