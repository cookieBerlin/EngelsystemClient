import Foundation
import SwiftData
import EngelsystemClientKit

/// The Watch app's fallback entry form logic (CLAUDE.md sync strategy): since CloudKit
/// sync between iOS and Watch isn't wired up yet, this is currently the only way to
/// configure the Watch app, not just the iCloud-unavailable fallback path.
@Observable
@MainActor
final class WatchSetupViewModel {
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

    /// See the iOS `InstanceSetupViewModel` counterpart for the full rationale — gates
    /// the Save button.
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

    /// Tests the server/key against `/info` and whether it resolves the `self`
    /// user-reference alias, without creating or saving anything — see the iOS
    /// `InstanceSetupViewModel.testConnection()` counterpart for the full rationale.
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
            featureSummary = ServerCapabilities.featureSummary(privileges: await apiClient.ownPrivileges(credential))
            connectionTested = true
        } catch {
            connectionTested = false
            errorMessage = Self.message(for: error)
        }
    }

    func save(in modelContext: ModelContext) async -> Bool {
        errorMessage = nil
        isTesting = true
        defer { isTesting = false }

        // The Watch always uses its own local keychain entry, independent of iCloud
        // sync, per CLAUDE.md's fallback-entry design.
        do {
            let instance = try await setupService.createInstance(
                name: name.trimmingCharacters(in: .whitespaces),
                baseURL: baseURL.trimmingCharacters(in: .whitespaces),
                apiKey: apiKey,
                store: LocalKeychainStore()
            )
            modelContext.insert(instance)
            try? modelContext.save()
            return true
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    /// Creates a demo instance (see `Instance.demoBaseURL`) so the Watch app can be
    /// tried without a real server or API key.
    func useDemoInstance(in modelContext: ModelContext) async -> Bool {
        name = "Demo"
        baseURL = Instance.demoBaseURL
        apiKey = "demo"
        return await save(in: modelContext)
    }

    private func invalidateTest() {
        connectionTested = false
    }

    static func message(for error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.userMessage
        }
        if error is KeychainError {
            return "Could not save the API key to the keychain."
        }
        return error.localizedDescription
    }
}
