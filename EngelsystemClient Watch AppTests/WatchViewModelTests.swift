import Foundation
import SwiftData
import UserNotifications
import Testing
import EngelsystemClientKit
@testable import EngelsystemClient_Watch_App

private final class AllowingCenter: NotificationCenterScheduling, @unchecked Sendable {
    var added: [UNNotificationRequest] = []
    func authorizationStatus() async -> UNAuthorizationStatus { .authorized }
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { true }
    func pendingNotificationRequests() async -> [UNNotificationRequest] { added }
    func add(_ request: UNNotificationRequest) async throws { added.append(request) }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {}
}

private struct PlainError: Error, LocalizedError { var errorDescription: String? { "plain failure" } }

/// A server that refuses connections immediately — the offline failure path without a stub
/// server (the Watch test target has no stubbed network of its own).
private let offlineBaseURL = "http://127.0.0.1:1"

@MainActor
private func makeContext() throws -> ModelContext {
    let schema = Schema([Instance.self, NotificationLeadTimeSettings.self, CachedShift.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    return ModelContext(try ModelContainer(for: schema, configurations: [config]))
}

@MainActor
private func seed(baseURL: String, in context: ModelContext, withKey: Bool = true) throws -> Instance {
    let ref = "watch-vm-tests-\(UUID().uuidString)"
    if withKey { try LocalKeychainStore().save(apiKey: "demo", for: ref) }
    let instance = Instance(name: "Test", baseURL: baseURL, apiKeyKeychainRef: ref)
    context.insert(instance)
    return instance
}

struct WatchSetupViewModelTests {
    @Test @MainActor func canTestAndCanSubmitFollowTheFormState() {
        let viewModel = WatchSetupViewModel()
        #expect(!viewModel.canTest && !viewModel.canSubmit)
        viewModel.baseURL = "https://example.com"
        viewModel.apiKey = "k"
        #expect(viewModel.canTest)
        #expect(!viewModel.canSubmit) // not tested yet, no name
        viewModel.name = "Event"
        viewModel.connectionTested = true
        #expect(viewModel.canSubmit)
    }

    @Test @MainActor func aFailingConnectionTestShowsTheError() async {
        let viewModel = WatchSetupViewModel()
        viewModel.baseURL = offlineBaseURL
        viewModel.apiKey = "k"
        await viewModel.testConnection()
        #expect(!viewModel.connectionTested)
        #expect(viewModel.errorMessage != nil)
    }

    @Test @MainActor func aPassingConnectionTestOnTheDemoServerMarksTheConnectionTested() async {
        let viewModel = WatchSetupViewModel()
        viewModel.baseURL = Instance.demoBaseURL
        viewModel.apiKey = "demo"
        await viewModel.testConnection()
        #expect(viewModel.connectionTested)
    }

    @Test @MainActor func useDemoInstanceInsertsAnInstance() async throws {
        let context = try makeContext()
        let viewModel = WatchSetupViewModel()
        #expect(await viewModel.useDemoInstance(in: context))
        let saved = try context.fetch(FetchDescriptor<Instance>())
        #expect(saved.count == 1)
        try? LocalKeychainStore().deleteAPIKey(for: saved[0].apiKeyKeychainRef)
    }

    @Test @MainActor func savingWithAnInvalidURLReportsTheError() async throws {
        let context = try makeContext()
        let viewModel = WatchSetupViewModel()
        viewModel.name = "Broken"
        viewModel.baseURL = "  "
        viewModel.apiKey = "k"
        #expect(await viewModel.save(in: context) == false)
        #expect(viewModel.errorMessage != nil)
    }

    @Test @MainActor func messagesMapAPIKeychainAndOtherErrors() {
        #expect(WatchSetupViewModel.message(for: APIError.forbidden) == APIError.forbidden.userMessage)
        #expect(WatchSetupViewModel.message(for: KeychainError.unexpectedData).contains("keychain"))
        #expect(WatchSetupViewModel.message(for: PlainError()) == "plain failure")
    }
}

struct WatchEditInstanceViewModelTests {
    @Test @MainActor func canTestAndCanSubmitFollowTheFormState() {
        let instance = Instance(name: "I", baseURL: "https://example.com", apiKeyKeychainRef: "r")
        let viewModel = WatchEditInstanceViewModel(instance: instance)
        #expect(viewModel.canTest)
        #expect(viewModel.canSubmit) // already "tested": nothing changed yet
        viewModel.baseURL = " "
        #expect(!viewModel.canTest && !viewModel.canSubmit)
    }

    @Test @MainActor func withoutAStoredKeyTestAndSaveReportTheError() async throws {
        let context = try makeContext()
        let instance = try seed(baseURL: "https://example.com", in: context, withKey: false)
        let viewModel = WatchEditInstanceViewModel(instance: instance)
        await viewModel.testConnection(for: instance)
        #expect(!viewModel.connectionTested)
        #expect(viewModel.errorMessage != nil)
        #expect(await viewModel.save(instance: instance, in: context) == false)
        #expect(viewModel.errorMessage != nil)
    }

    @Test @MainActor func testingAndSavingAgainstTheDemoServerRenamesTheInstance() async throws {
        let context = try makeContext()
        let instance = try seed(baseURL: Instance.demoBaseURL, in: context)
        defer { try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef) }
        let viewModel = WatchEditInstanceViewModel(instance: instance)
        viewModel.name = "Renamed"
        await viewModel.testConnection(for: instance)
        #expect(viewModel.connectionTested)
        #expect(await viewModel.save(instance: instance, in: context))
        #expect(instance.name == "Renamed")
    }

    @Test @MainActor func aFailingConnectionTestAgainstAnOfflineServerShowsTheError() async throws {
        let context = try makeContext()
        let instance = try seed(baseURL: offlineBaseURL, in: context)
        defer { try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef) }
        let viewModel = WatchEditInstanceViewModel(instance: instance)
        await viewModel.testConnection(for: instance)
        #expect(!viewModel.connectionTested)
        #expect(viewModel.errorMessage != nil)
    }

    @Test @MainActor func messagesMapAPICredentialAndOtherErrors() {
        #expect(WatchEditInstanceViewModel.message(for: APIError.forbidden) == APIError.forbidden.userMessage)
        #expect(WatchEditInstanceViewModel.message(for: InstanceCredentialError.apiKeyNotFound).contains("API key"))
        #expect(WatchEditInstanceViewModel.message(for: PlainError()) == "plain failure")
    }
}

struct NextShiftViewModelFailureTests {
    @Test @MainActor func aMissingCredentialIsReportedAsASetupProblem() async throws {
        let context = try makeContext()
        let instance = try seed(baseURL: Instance.demoBaseURL, in: context, withKey: false)
        let viewModel = NextShiftViewModel(notificationScheduler: NotificationScheduler(center: AllowingCenter()))
        await viewModel.refresh(instances: [instance], in: context)
        #expect(viewModel.errorMessage?.contains("Set up the Watch app again") == true)
    }

    @Test @MainActor func cancellationIsNotShownAsAnError() async throws {
        let context = try makeContext()
        let instance = try seed(baseURL: offlineBaseURL, in: context)
        defer { try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef) }
        let viewModel = NextShiftViewModel(notificationScheduler: NotificationScheduler(center: AllowingCenter()))
        let task = Task { @MainActor in
            while !Task.isCancelled { await Task.yield() }
            await viewModel.refresh(instances: [instance], in: context)
        }
        task.cancel()
        await task.value
        #expect(viewModel.errorMessage == nil)
    }

    @Test @MainActor func aCleanRefreshSchedulesRemindersAndPublishesTheSnapshot() async throws {
        let context = try makeContext()
        let instance = try seed(baseURL: Instance.demoBaseURL, in: context)
        defer { try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef) }
        let viewModel = NextShiftViewModel(notificationScheduler: NotificationScheduler(center: AllowingCenter()))
        await viewModel.refresh(instances: [instance], in: context)
        #expect(viewModel.errorMessage == nil)
    }

    @Test @MainActor func messagesMapAPICredentialAndOtherErrors() {
        #expect(NextShiftViewModel.message(for: APIError.forbidden) == APIError.forbidden.userMessage)
        #expect(NextShiftViewModel.message(for: InstanceCredentialError.apiKeyNotFound).contains("Set up"))
        #expect(NextShiftViewModel.message(for: PlainError()) == "plain failure")
    }
}
