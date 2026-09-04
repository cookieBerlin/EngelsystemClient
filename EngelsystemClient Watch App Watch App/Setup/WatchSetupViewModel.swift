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
    var baseURL: String = ""
    var apiKey: String = ""
    /// Fallback for servers that 404 on the `self` path-parameter alias — see
    /// `Instance.userID`. Kept as text here since it's an optional numeric field on a
    /// form; parsed on submit.
    var userIDText: String = ""

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

    func testAndSave(in modelContext: ModelContext) async -> Bool {
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
        return await testAndSave(in: modelContext)
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
