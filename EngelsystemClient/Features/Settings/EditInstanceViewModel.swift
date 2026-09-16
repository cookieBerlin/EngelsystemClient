import Foundation
import SwiftData
import EngelsystemClientKit

/// Backs the "Edit Instance" sheet (name + server URL) reached from `SettingsView`'s
/// instance detail screen — separate from `UpdateAPIKeyViewModel` since editing the
/// name/server doesn't need a new API key, just the existing one (resolved here rather
/// than re-entered) to re-test the connection.
@Observable
@MainActor
final class EditInstanceViewModel {
    var name: String
    var baseURL: String
    /// Fallback for servers that 404 on the `self` path-parameter alias — see
    /// `Instance.userID`. Kept as text here since it's an optional numeric field on a
    /// form; parsed on submit.
    var userIDText: String
    var isTesting = false
    var errorMessage: String?

    private let setupService: InstanceSetupService
    private let credentialResolver: InstanceCredentialResolver

    init(
        instance: Instance,
        setupService: InstanceSetupService = InstanceSetupService(),
        credentialResolver: InstanceCredentialResolver = InstanceCredentialResolver()
    ) {
        self.name = instance.name
        self.baseURL = instance.normalizedBaseURL
        self.userIDText = instance.userID.map(String.init) ?? ""
        self.setupService = setupService
        self.credentialResolver = credentialResolver
    }

    var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !isTesting
    }

    /// Tests the (possibly changed) name/server against the instance's existing API
    /// key and, on success, updates `instance` in place and explicitly persists the
    /// `ModelContext`. The explicit `save()` matters here: SwiftData's autosave only
    /// fires on certain app-lifecycle events (e.g. resigning active), which a debug
    /// rebuild-and-relaunch from Xcode skips entirely (it kills the old process
    /// directly rather than backgrounding it) — without this, an edit made shortly
    /// before the next Xcode "Run" could be silently lost even though the sheet showed
    /// success and dismissed. Root-caused 2026-09-16 after a user-reported case of a
    /// manually re-entered `userID` reverting to `nil` after a rebuild.
    func save(instance: Instance, in modelContext: ModelContext) async -> Bool {
        errorMessage = nil
        isTesting = true
        defer { isTesting = false }

        do {
            let credential = try credentialResolver.credential(for: instance)
            try await setupService.updateServerDetails(
                for: instance,
                name: name.trimmingCharacters(in: .whitespaces),
                baseURL: baseURL.trimmingCharacters(in: .whitespaces),
                apiKey: credential.apiKey,
                userID: Int(userIDText.trimmingCharacters(in: .whitespaces))
            )
            try? modelContext.save()
            return true
        } catch {
            errorMessage = SyncErrorMapper.message(for: error)
            return false
        }
    }
}
