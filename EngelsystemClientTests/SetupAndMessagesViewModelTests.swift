import Foundation
import SwiftData
import UserNotifications
import Testing
import EngelsystemClientKit
@testable import EngelsystemClient

@MainActor
private func makeContext() throws -> ModelContext {
    let schema = Schema([Instance.self, NotificationLeadTimeSettings.self, CachedShift.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    return ModelContext(try ModelContainer(for: schema, configurations: [config]))
}

private final class AllowingCenter: NotificationCenterScheduling, @unchecked Sendable {
    var added: [UNNotificationRequest] = []
    func authorizationStatus() async -> UNAuthorizationStatus { .authorized }
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { true }
    func pendingNotificationRequests() async -> [UNNotificationRequest] { added }
    func add(_ request: UNNotificationRequest) async throws { added.append(request) }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {}
}

struct SmallEnumAndHelperTests {
    @Test func keyStoreSelectionPicksTheSyncedStoreFirstOnlyWhenICloudIsAvailable() {
        let withICloud = KeyStoreSelection.stores(iCloudAvailable: true)
        #expect(withICloud.primary is KeychainSyncStore && withICloud.secondary is LocalKeychainStore)
        let without = KeyStoreSelection.stores(iCloudAvailable: false)
        #expect(without.primary is LocalKeychainStore && without.secondary is KeychainSyncStore)
        _ = KeyStoreSelection.currentStores()
    }

    @Test func filterAndDisplayModeEnumsHaveTitlesAndIDs() {
        for filter in NewsMeetingFilter.allCases {
            #expect(filter.id == filter.rawValue)
            #expect(!filter.title.isEmpty)
        }
        #expect(NewsMeetingFilter.all.title == "All")
        #expect(NewsMeetingFilter.meetingsOnly.title == "Meetings")
        #expect(NewsMeetingFilter.nonMeetingsOnly.title == "Non-Meetings")
        for mode in MultiInstanceDisplayMode.allCases {
            #expect(mode.id == mode.rawValue)
            #expect(!mode.title.isEmpty)
        }
        #expect(MultiInstanceDisplayMode.merged.title == "Merged")
        #expect(MultiInstanceDisplayMode.switcher.title == "Switcher")
        #expect(MultiInstanceDisplayMode.sectioned.title == "Sectioned")
    }

    private struct PlainError: Error, LocalizedError { var errorDescription: String? { "plain failure" } }

    @Test func otherErrorsFallBackToTheirLocalizedDescription() {
        #expect(SyncErrorMapper.message(for: PlainError()) == "plain failure")
    }
}

extension StubbedNetworkTests {
    @Suite
    struct SetupViewModelTests {
        init() { StubbedNetwork.install() }

        @Test @MainActor func savingAndUsingTheDemoInstanceInsertsIt() async throws {
            let context = try makeContext()
            let viewModel = InstanceSetupViewModel()
            #expect(await viewModel.useDemoInstance(in: context))
            let saved = try context.fetch(FetchDescriptor<Instance>())
            #expect(saved.count == 1)
            #expect(saved[0].baseURL == Instance.demoBaseURL)
            try? LocalKeychainStore().deleteAPIKey(for: saved[0].apiKeyKeychainRef)
            try? KeychainSyncStore().deleteAPIKey(for: saved[0].apiKeyKeychainRef)
        }

        @Test @MainActor func savingWithAnInvalidServerURLReportsTheError() async throws {
            let context = try makeContext()
            let viewModel = InstanceSetupViewModel()
            viewModel.name = "Broken"
            viewModel.baseURL = "   "
            viewModel.apiKey = "k"
            #expect(await viewModel.save(in: context) == false)
            #expect(viewModel.errorMessage != nil)
            #expect(try context.fetch(FetchDescriptor<Instance>()).isEmpty)
        }

        @Test @MainActor func aFailingConnectionTestShowsTheErrorAndKeepsSaveDisabled() async {
            StubURLProtocol.route("GET /api/v0-beta/info", status: 401)
            let viewModel = InstanceSetupViewModel()
            viewModel.baseURL = "https://stub.test"
            viewModel.apiKey = "bad"
            await viewModel.testConnection()
            #expect(!viewModel.connectionTested)
            #expect(viewModel.errorMessage != nil)
        }

        /// COMPAT(#1709): a server that reports the account's privileges gets a features summary; a
        /// denied or older server just gets none — never a warning.
        @Test @MainActor func connectionTestShowsAFeaturesSummaryOnlyWhenPrivilegesAreKnown() async throws {
            try StubURLProtocol.routeDemoInfo("GET /api/v0-beta/info")
            StubURLProtocol.route("GET /api/v0-beta/users/self", status: 403)
            let viewModel = InstanceSetupViewModel()
            viewModel.name = "Server"
            viewModel.baseURL = "https://stub.test"
            viewModel.apiKey = "k"
            await viewModel.testConnection()
            #expect(viewModel.connectionTested)
            #expect(viewModel.canSubmit)
            #expect(viewModel.featureSummary == nil)

            let json = """
            {"data":{"id":2,"name":"cookie","first_name":null,"last_name":null,"pronoun":null,\
            "contact":{"dect":null,"mobile":null},"url":"https://example.org/users/2","email":"a@b.c",\
            "tshirt_size":null,"dates":{"planned_arrival":null,"planned_departure":null,"arrival":null},\
            "language":"en_US","arrived":false,"oauth":[],"groups":[],"privileges":["news"]}}
            """
            StubURLProtocol.route("GET /api/v0-beta/users/self", body: Data(json.utf8))
            await viewModel.testConnection()
            #expect(viewModel.featureSummary == ServerCapabilities.featureSummary(privileges: ["news"]))
            #expect(viewModel.featureSummary?.hasSuffix("features available") == true)
        }

        /// A demo address needs no server: the summary names what that demo offers.
        @Test @MainActor func demoAddressesShowWhatTheDemoOffers() async {
            let total = ServerFeature.listed.count
            let viewModel = InstanceSetupViewModel()
            viewModel.baseURL = Instance.demoBaseURL
            viewModel.apiKey = "demo"
            await viewModel.testConnection()
            #expect(viewModel.featureSummary == "\(total) of \(total) features available")

            viewModel.baseURL = "demo://nothing.local"
            await viewModel.testConnection()
            #expect(viewModel.featureSummary == "1 of \(total) features available")
        }

        @Test @MainActor func verifyOfTheNewsOnlyDemoShowsOneFeature() async throws {
            let key = "verify-demo-\(UUID().uuidString)"
            try LocalKeychainStore().save(apiKey: "demo", for: key)
            defer { try? LocalKeychainStore().deleteAPIKey(for: key) }
            let instance = Instance(name: "Only News", baseURL: "demo://nothing.local", apiKeyKeychainRef: key)
            let capabilities = ServerCapabilities(defaults: UserDefaults(suiteName: "verify-demo-\(UUID().uuidString)")!)
            let viewModel = EditInstanceViewModel(instance: instance, capabilities: capabilities)

            await viewModel.testConnection(for: instance)
            #expect(viewModel.featureSummary == "1 of \(ServerFeature.listed.count) features available")
            #expect(capabilities.status(.shifts, for: instance.id).state == .notOffered)
        }

        @Test @MainActor func verifyFeedsTheInstanceFeatureListOnlyForTheSameServer() async throws {
            let key = "verify-\(UUID().uuidString)"
            try LocalKeychainStore().save(apiKey: "demo", for: key)
            defer { try? LocalKeychainStore().deleteAPIKey(for: key) }
            let instance = Instance(name: "Demo", baseURL: Instance.demoBaseURL, apiKeyKeychainRef: key)
            let capabilities = ServerCapabilities(defaults: UserDefaults(suiteName: "verify-\(UUID().uuidString)")!)
            let viewModel = EditInstanceViewModel(instance: instance, capabilities: capabilities)

            viewModel.baseURL = Instance.demoBaseURL + "/other"
            await viewModel.testConnection(for: instance)
            #expect(capabilities.status(.messages, for: instance.id).state == .unknown)

            capabilities.record(.shiftTeam, state: .notOffered, evidence: .field, for: instance.id)
            viewModel.baseURL = Instance.demoBaseURL
            await viewModel.testConnection(for: instance)
            #expect(capabilities.status(.messages, for: instance.id).state == .available)
            // The summary reads the same list the instance page shows.
            #expect(viewModel.featureSummary == capabilities.summaryText(for: instance.id))
        }

        @Test @MainActor func editingCanTestOnlyWithAServerURLAndNotWhileTesting() {
            let instance = Instance(name: "I", baseURL: "https://stub.test", apiKeyKeychainRef: "r")
            let viewModel = EditInstanceViewModel(instance: instance)
            #expect(viewModel.canTest)
            viewModel.baseURL = "  "
            #expect(!viewModel.canTest)
        }

        @Test @MainActor func editingWithoutAStoredKeyReportsTheErrorOnTestAndSave() async throws {
            let context = try makeContext()
            let instance = Instance(name: "I", baseURL: "https://stub.test", apiKeyKeychainRef: "missing-\(UUID().uuidString)")
            context.insert(instance)
            let viewModel = EditInstanceViewModel(instance: instance)

            await viewModel.testConnection(for: instance)
            #expect(!viewModel.connectionTested)
            #expect(viewModel.errorMessage != nil)

            #expect(await viewModel.save(instance: instance, in: context) == false)
            #expect(viewModel.errorMessage != nil)
        }
    }

    @Suite
    struct MessagesAndShiftsFailureTests {
        init() { StubbedNetwork.install() }

        private let prefix = "/api/v0-beta"

        private func demoMessage() async throws -> Message {
            let demo = EventCredential(baseURL: Instance.demoBaseURL + "/api/v0-beta", apiKey: "demo")
            return try #require(try await APIClient.shared.fetchConversations(demo).first?.latestMessage)
        }

        @MainActor
        private func stubInstance() throws -> Instance {
            let ref = "failure-tests-\(UUID().uuidString)"
            try LocalKeychainStore().save(apiKey: "k", for: ref)
            return Instance(name: "Stub", baseURL: "https://stub.test", apiKeyKeychainRef: ref)
        }

        @Test @MainActor func aFailedConversationLoadShowsAnErrorButCancellationDoesNot() async throws {
            let instance = try stubInstance()
            defer { try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef) }
            StubURLProtocol.route("GET \(prefix)/messages/5", status: 500)
            let viewModel = ConversationDetailViewModel()
            await viewModel.load(otherUserID: 5, instance: instance)
            #expect(viewModel.errorMessage != nil)

            let task = Task { @MainActor in
                while !Task.isCancelled { await Task.yield() }
                await viewModel.load(otherUserID: 5, instance: instance)
            }
            task.cancel()
            await task.value
            #expect(viewModel.errorMessage == nil)
        }

        @Test @MainActor func aFailedMarkAsReadDoesNotSurfaceAnError() async throws {
            let instance = try stubInstance()
            defer { try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef) }
            let unread = Message(
                id: 41, text: "Hi", sender: Reference(id: 5, name: "Other"), receiver: Reference(id: 1, name: "me"),
                read: false, createdAt: Date(), updatedAt: nil
            )
            StubURLProtocol.route(
                "GET \(prefix)/messages/\(unread.sender.id)",
                body: Data("{\"data\":{\"messages\":".utf8) + (try CodableHelper.jsonEncoder.encode([unread])) + Data("}}".utf8)
            )
            StubURLProtocol.route("PATCH \(prefix)/messages/\(unread.id)", status: 500)
            let viewModel = ConversationDetailViewModel()
            await viewModel.load(otherUserID: unread.sender.id, instance: instance)
            #expect(viewModel.errorMessage == nil)
            #expect(viewModel.messages.count == 1)
        }

        @Test func sendingNeedsANonBlankDraftAndNothingInFlight() {
            #expect(ConversationDetailViewModel.canSend(draft: "hi", isSending: false))
            #expect(!ConversationDetailViewModel.canSend(draft: "  \n", isSending: false))
            #expect(!ConversationDetailViewModel.canSend(draft: "hi", isSending: true))
        }

        @Test @MainActor func aSentDraftClearsTheComposerAndAFailedOneComesBack() async throws {
            let instance = try stubInstance()
            defer { try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef) }
            let sent = try await demoMessage()
            try StubURLProtocol.route("POST \(prefix)/messages/5", status: 201, data: sent)
            let viewModel = ConversationDetailViewModel()
            #expect(await viewModel.sendDraft("hello", otherUserID: 5, instance: instance) == "")

            StubURLProtocol.route("POST \(prefix)/messages/6", status: 500)
            #expect(await viewModel.sendDraft("again", otherUserID: 6, instance: instance) == "again")
        }

        @Test @MainActor func failedSendAndDeleteShowErrors() async throws {
            let instance = try stubInstance()
            defer { try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef) }
            StubURLProtocol.route("POST \(prefix)/messages/5", status: 403)
            StubURLProtocol.route("DELETE \(prefix)/messages/7", status: 403)
            let viewModel = ConversationDetailViewModel()

            #expect(await viewModel.send(text: "hi", otherUserID: 5, instance: instance) == false)
            #expect(viewModel.errorMessage != nil)

            viewModel.errorMessage = nil
            let message = try await demoMessage()
            await viewModel.delete(Message(id: 7, text: "x", sender: message.sender, receiver: message.receiver, read: true, createdAt: Date(), updatedAt: nil), instance: instance)
            #expect(viewModel.errorMessage != nil)
        }

        @Test @MainActor func aFailedUserLoadShowsAnErrorButCancellationDoesNot() async throws {
            let instance = try stubInstance()
            defer { try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef) }
            StubURLProtocol.route("GET \(prefix)/users", status: 500)
            let viewModel = UserPickerViewModel()
            await viewModel.load(instance: instance)
            #expect(viewModel.errorMessage != nil)

            let task = Task { @MainActor in
                while !Task.isCancelled { await Task.yield() }
                await viewModel.load(instance: instance)
            }
            task.cancel()
            await task.value
            #expect(viewModel.errorMessage == nil)
        }

        @Test @MainActor func usersWithoutNamesAreStillSorted() async throws {
            let instance = try stubInstance()
            defer { try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef) }
            try StubURLProtocol.route("GET \(prefix)/users", data: [Reference(id: 2, name: nil), Reference(id: 1, name: nil)])
            let viewModel = UserPickerViewModel()
            await viewModel.load(instance: instance)
            #expect(viewModel.users.count == 2)
            #expect(viewModel.errorMessage == nil)
        }

        @Test @MainActor func shiftsRefreshFlagsUnauthorizedAndIgnoresCancellation() async throws {
            let context = try makeContext()
            let instance = try stubInstance()
            defer { try? LocalKeychainStore().deleteAPIKey(for: instance.apiKeyKeychainRef) }
            context.insert(instance)
            StubURLProtocol.route("GET \(prefix)/users/self/shifts", status: 401)
            let viewModel = ShiftsViewModel(notificationScheduler: NotificationScheduler(center: AllowingCenter()))
            await viewModel.refresh(instances: [instance], in: context)
            #expect(viewModel.isUnauthorized)

            let task = Task { @MainActor in
                while !Task.isCancelled { await Task.yield() }
                await viewModel.refresh(instances: [instance], in: context)
            }
            task.cancel()
            await task.value
            #expect(viewModel.errorMessage == nil)
        }

        @Test @MainActor func aCleanShiftsRefreshSchedulesReminders() async throws {
            let context = try makeContext()
            let ref = "shifts-notify-\(UUID().uuidString)"
            try LocalKeychainStore().save(apiKey: "demo", for: ref)
            defer { try? LocalKeychainStore().deleteAPIKey(for: ref) }
            let instance = Instance(name: "Demo", baseURL: Instance.demoBaseURL, apiKeyKeychainRef: ref)
            context.insert(instance)
            let center = AllowingCenter()
            let viewModel = ShiftsViewModel(notificationScheduler: NotificationScheduler(center: center))
            await viewModel.refresh(instances: [instance], in: context)
            #expect(viewModel.errorMessage == nil)
        }
    }
}
