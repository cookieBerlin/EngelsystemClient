import Foundation
import SwiftData
import EngelsystemClientKit

/// Backs the combined "Edit Instance" sheet (name, server URL, User ID, API Key)
/// reached from `SettingsView`'s instance detail screen. Merges what used to be two
/// separate actions/sheets — "Edit Name / Server" and "Update API Key" — into one
/// (2026-09-17 multi-active-instance redesign, CLAUDE.md): the API Key field is left
/// blank by default and blank means "keep the existing key" (resolved here via
/// `InstanceCredentialResolver`, same as before) — only fill it in to actually change
/// it. Activating/deactivating an instance is a separate, instant action (a swipe
/// action on the instance row in `SettingsView`), not part of this dialog.
@Observable
@MainActor
final class EditInstanceViewModel {
    var name: String
    var baseURL: String
    /// Fallback for servers that 404 on the `self` path-parameter alias — see
    /// `Instance.userID`. Kept as text here since it's an optional numeric field on a
    /// form; parsed on submit.
    var userIDText: String
    /// Left blank on open (never pre-filled with the existing key, for the same reason
    /// `UpdateAPIKeyView` never showed one) — blank on save means "keep the existing key".
    var apiKey: String = ""
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

    /// Tests the (possibly changed) name/server/key against the server and, on success,
    /// updates `instance` in place and explicitly persists the `ModelContext`. The
    /// explicit `save()` matters here: SwiftData's autosave only fires on certain
    /// app-lifecycle events (e.g. resigning active), which a debug rebuild-and-relaunch
    /// from Xcode skips entirely (it kills the old process directly rather than
    /// backgrounding it) — without this, an edit made shortly before the next Xcode
    /// "Run" could be silently lost even though the sheet showed success and dismissed.
    /// Root-caused 2026-09-16 after a user-reported case of a manually re-entered
    /// `userID` reverting to `nil` after a rebuild.
    func save(instance: Instance, in modelContext: ModelContext) async -> Bool {
        errorMessage = nil
        isTesting = true
        defer { isTesting = false }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespaces)
        let newKeyToStore = trimmedKey.isEmpty ? nil : trimmedKey

        let primaryStore: APIKeyStore = ICloudAvailability.isAvailable ? KeychainSyncStore() : LocalKeychainStore()
        let secondaryStore: APIKeyStore = ICloudAvailability.isAvailable ? LocalKeychainStore() : KeychainSyncStore()

        do {
            let existingCredential = try credentialResolver.credential(for: instance)
            let effectiveAPIKey = newKeyToStore ?? existingCredential.apiKey

            try await setupService.updateInstance(
                for: instance,
                name: name.trimmingCharacters(in: .whitespaces),
                baseURL: baseURL.trimmingCharacters(in: .whitespaces),
                apiKey: effectiveAPIKey,
                newAPIKeyToStore: newKeyToStore,
                userID: Int(userIDText.trimmingCharacters(in: .whitespaces)),
                store: primaryStore
            )
            // Which store (iCloud vs. local) the key originally landed in isn't tracked
            // on `Instance`, so mirror a freshly typed key into both — otherwise a stale
            // value could linger in whichever store `InstanceCredentialResolver` happens
            // to check first (same reasoning as the old `UpdateAPIKeyViewModel`).
            if let newKeyToStore {
                try? secondaryStore.save(apiKey: newKeyToStore, for: instance.apiKeyKeychainRef)
            }
            try? modelContext.save()
            return true
        } catch {
            errorMessage = SyncErrorMapper.message(for: error)
            return false
        }
    }
}
