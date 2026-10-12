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
    /// Fallback for servers that 404 on the `self` path-parameter alias — see
    /// `Instance.userID`. Kept as text here since it's an optional numeric field on a
    /// form; parsed on submit. Only shown in the UI once `testConnection()` has
    /// determined it's actually needed (`connectionTested && !selfReferenceWorks`).
    var userIDText: String = ""

    var isTesting = false
    var errorMessage: String?

    /// Set once `testConnection()` succeeds against the currently entered
    /// server/key; reset by `invalidateTest()` whenever `baseURL`/`apiKey` change, so
    /// Save always reflects a fresh test of what's currently in the form rather than a
    /// stale result from an earlier value. Gates both the Save button and whether the
    /// User ID field is shown at all.
    var connectionTested = false
    /// Result of the last `testConnection()`'s `self`-alias probe — see
    /// `Instance.selfReferenceWorks`/`APIClient.selfUserReferenceWorks`. Only
    /// meaningful once `connectionTested` is true.
    var selfReferenceWorks = true

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

    /// Tests the server/key against `/info` and, separately, whether this server
    /// resolves the `self` user-reference alias (`APIClient.selfUserReferenceWorks`) —
    /// without creating or saving anything. Lets the User ID field only appear once
    /// it's actually known to be needed, instead of always showing it up front. If the
    /// server turns out to support `self` after all, any previously typed User ID is
    /// cleared so a stale, no-longer-needed value can't silently get saved once Save
    /// is pressed.
    func testConnection() async {
        errorMessage = nil
        isTesting = true
        defer { isTesting = false }

        let credential = EventCredential(
            baseURL: Instance.apiBasePath(for: baseURL.trimmingCharacters(in: .whitespaces)),
            apiKey: apiKey
        )
        do {
            _ = try await apiClient.fetchInfo(credential)
            selfReferenceWorks = await apiClient.selfUserReferenceWorks(credential)
            if selfReferenceWorks {
                userIDText = ""
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
                store: store,
                userID: Int(userIDText.trimmingCharacters(in: .whitespaces))
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
