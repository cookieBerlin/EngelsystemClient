import Foundation
import SwiftData
import EngelsystemClientKit

@Observable
@MainActor
final class InstanceSetupViewModel {
    var name: String = ""
    var baseURL: String = ""
    var apiKey: String = ""

    var isTesting = false
    var errorMessage: String?

    private let setupService: InstanceSetupService

    init(setupService: InstanceSetupService = InstanceSetupService()) {
        self.setupService = setupService
    }

    var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
            && !isTesting
    }

    /// Tests the connection against `/info` and, on success, creates a new `Instance`
    /// including a keychain entry. Returns `true` if the instance was saved.
    func testAndSave(in modelContext: ModelContext) async -> Bool {
        errorMessage = nil
        isTesting = true
        defer { isTesting = false }

        let store: APIKeyStore = ICloudAvailability.isAvailable ? KeychainSyncStore() : LocalKeychainStore()
        do {
            let instance = try await setupService.createInstance(
                name: name.trimmingCharacters(in: .whitespaces),
                baseURL: baseURL.trimmingCharacters(in: .whitespaces),
                apiKey: apiKey,
                store: store
            )
            modelContext.insert(instance)
            return true
        } catch {
            errorMessage = SyncErrorMapper.message(for: error)
            return false
        }
    }

    /// Creates a demo instance (see `Instance.demoBaseURL`) so the app can be tried
    /// without a real server or API key. Goes through the same save path as a real
    /// instance — `APIClient` is what actually short-circuits to mock data.
    func useDemoInstance(in modelContext: ModelContext) async -> Bool {
        name = "Demo"
        baseURL = Instance.demoBaseURL
        apiKey = "demo"
        return await testAndSave(in: modelContext)
    }
}
