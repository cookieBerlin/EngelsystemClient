import Foundation
import SwiftData
import EngelsystemClientKit

@Observable
@MainActor
final class InstanceSetupViewModel {
    var name: String = ""
    var baseURL: String = "" {
        didSet { invalidateTest() }
    }
    var apiKey: String = "" {
        didSet { invalidateTest() }
    }

    var isTesting = false
    var errorMessage: String?
    /// "5 of 8 features available" after a successful `testConnection` against a server that
    /// reports the account's privileges (PR #1709); nil otherwise. Never an error.
    var featureSummary: String?

    /// Set once `testConnection()` succeeds against the currently entered
    /// server/key; reset by `invalidateTest()` whenever `baseURL`/`apiKey` change, so
    /// Save always reflects a fresh test of what's currently in the form rather than a
    /// stale result from an earlier value. Gates the Save button.
    var connectionTested = false

    private let apiClient: APIClient
    private let setupService: InstanceSetupService

    init(apiClient: APIClient = .shared, setupService: InstanceSetupService = InstanceSetupService()) {
        self.apiClient = apiClient
        self.setupService = setupService
    }

    var canTest: Bool {
        !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
            && !isTesting
    }

    var canSubmit: Bool {
        connectionTested
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
            && !isTesting
    }

    /// Tests the server/key against `/info` (and a data request, for the 403 warning) without
    /// creating or saving anything.
    func testConnection() async {
        errorMessage = nil
        featureSummary = nil
        isTesting = true
        defer { isTesting = false }

        let credential = EventCredential(
            baseURL: Instance.apiBasePath(for: baseURL.trimmingCharacters(in: .whitespaces)),
            apiKey: apiKey
        )
        do {
            _ = try await apiClient.fetchInfo(credential)
            let address = baseURL.trimmingCharacters(in: .whitespaces)
            if address.hasPrefix(DemoScenario.scheme) {
                featureSummary = ServerCapabilities.demoSummaryText(newsOnly: DemoScenario.isNewsOnly(address: address))
            } else {
                featureSummary = ServerCapabilities.featureSummary(privileges: await apiClient.ownPrivileges(credential))
            }
            connectionTested = true
        } catch {
            connectionTested = false
            errorMessage = SyncErrorMapper.message(for: error)
        }
    }

    /// Creates the `Instance`. Only reachable once `testConnection()` has succeeded
    /// (`canSubmit` requires `connectionTested`) — re-runs both server checks anyway
    /// via `InstanceSetupService.createInstance`, so this stays correct even if
    /// something about the server changed in the moment between testing and saving.
    func save(in modelContext: ModelContext) async -> Bool {
        errorMessage = nil
        isTesting = true
        defer { isTesting = false }

        let store = KeyStoreSelection.currentStores().primary
        do {
            let instance = try await setupService.createInstance(
                name: name.trimmingCharacters(in: .whitespaces),
                baseURL: baseURL.trimmingCharacters(in: .whitespaces),
                apiKey: apiKey,
                store: store
            )
            modelContext.insert(instance)
            try? modelContext.save()
            return true
        } catch {
            errorMessage = SyncErrorMapper.message(for: error)
            return false
        }
    }

    private func invalidateTest() {
        connectionTested = false
    }

    /// Creates a demo instance (see `Instance.demoBaseURL`) so the app can be tried
    /// without a real server or API key. Goes through the same save path as a real
    /// instance — `APIClient` is what actually short-circuits to mock data.
    func useDemoInstance(in modelContext: ModelContext) async -> Bool {
        name = "Demo"
        baseURL = Instance.demoBaseURL
        apiKey = "demo"
        return await save(in: modelContext)
    }
}
