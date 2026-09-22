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
    /// Fallback for servers that 404 on the `self` path-parameter alias — see
    /// `Instance.userID`. Kept as text here since it's an optional numeric field on a
    /// form; parsed on submit. Only shown in the UI once `testConnection()` has
    /// determined it's actually needed (`connectionTested && !selfReferenceWorks`).
    var userIDText: String = ""

    var isTesting = false
    var errorMessage: String?

    /// See the iOS `InstanceSetupViewModel` counterpart for the full rationale — gates
    /// the Save button and whether the User ID field is shown at all.
    var connectionTested = false
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

    /// Tests the server/key against `/info` and whether it resolves the `self`
    /// user-reference alias, without creating or saving anything — see the iOS
    /// `InstanceSetupViewModel.testConnection()` counterpart for the full rationale.
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
                store: LocalKeychainStore(),
                userID: Int(userIDText.trimmingCharacters(in: .whitespaces))
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

    private static func message(for error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.userMessage
        }
        if error is KeychainError {
            return "Could not save the API key to the keychain."
        }
        return error.localizedDescription
    }
}
