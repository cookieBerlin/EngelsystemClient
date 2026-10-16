import Foundation
import SwiftData
import EngelsystemClientKit

/// Backs the combined "Edit Instance" sheet (name, server URL, API Key)
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
    var baseURL: String {
        didSet { connectionTested = false }
    }
    /// Left blank on open (never pre-filled with the existing key, for the same reason
    /// `UpdateAPIKeyView` never showed one) — blank on save means "keep the existing key".
    var apiKey: String = "" {
        didSet { connectionTested = false }
    }
    var isTesting = false
    var errorMessage: String?
    /// "5 of 8 features available" after a successful `testConnection` against a server that
    /// reports the account's privileges (PR #1709); nil otherwise. Never an error.
    var featureSummary: String?

    /// Gates the Save button (`canSubmit`) and drives the "Test Connection" button's
    /// own display (progress/checkmark/label); reset whenever `baseURL`/`apiKey`
    /// change, so editing either forces a fresh "Test Connection" tap before Save
    /// re-enables (2026-09-21, at the user's explicit request — Save was previously
    /// left always-enabled here since `save()` already re-verifies internally
    /// regardless, but that let it stay enabled even right after an edit nobody had
    /// actually tested yet). Starts `true`, since an already-open dialog for an
    /// existing instance reflects a state that was already verified at creation or the
    /// previous save.
    var connectionTested = true

    private let apiClient: APIClient
    private let setupService: InstanceSetupService
    private let credentialResolver: InstanceCredentialResolver
    private let capabilities: ServerCapabilities

    init(
        instance: Instance,
        apiClient: APIClient = .shared,
        setupService: InstanceSetupService = InstanceSetupService(),
        credentialResolver: InstanceCredentialResolver = InstanceCredentialResolver(),
        capabilities: ServerCapabilities = .shared
    ) {
        self.capabilities = capabilities
        self.name = instance.name
        self.baseURL = instance.normalizedBaseURL
        self.apiClient = apiClient
        self.setupService = setupService
        self.credentialResolver = credentialResolver
    }

    var canSubmit: Bool {
        connectionTested
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !isTesting
    }

    var canTest: Bool {
        !baseURL.trimmingCharacters(in: .whitespaces).isEmpty && !isTesting
    }

    /// Re-verifies the server/key (resolving the existing key via
    /// `InstanceCredentialResolver` when the API Key field is left blank, same
    /// resolution `save()` uses) — without saving anything, so pressing "Test Connection"
    /// alone never mutates the store (Verify previews, Save commits).
    func testConnection(for instance: Instance) async {
        errorMessage = nil
        featureSummary = nil
        isTesting = true
        defer { isTesting = false }

        do {
            let existingCredential = try credentialResolver.credential(for: instance)
            let trimmedKey = apiKey.trimmingCharacters(in: .whitespaces)
            let effectiveAPIKey = trimmedKey.isEmpty ? existingCredential.apiKey : trimmedKey
            let credential = EventCredential(
                baseURL: Instance.apiBasePath(for: baseURL.trimmingCharacters(in: .whitespaces)),
                apiKey: effectiveAPIKey
            )
            _ = try await apiClient.fetchInfo(credential)
            let privileges = await apiClient.ownPrivileges(credential)
            featureSummary = ServerCapabilities.featureSummary(privileges: privileges)
            // The same finding feeds the instance's Features list, as long as it is still the same server.
            if credential.baseURL == Instance.apiBasePath(for: instance.normalizedBaseURL) {
                capabilities.applyPrivileges(privileges, for: instance.id)
            }
            connectionTested = true
        } catch {
            connectionTested = false
            errorMessage = SyncErrorMapper.message(for: error)
        }
    }

    /// Tests the (possibly changed) name/server/key against the server and, on success,
    /// updates `instance` in place and explicitly persists the `ModelContext`. The
    /// explicit `save()` matters here: SwiftData's autosave only fires on certain
    /// app-lifecycle events (e.g. resigning active), which a debug rebuild-and-relaunch
    /// from Xcode skips entirely (it kills the old process directly rather than
    /// backgrounding it) — without this, an edit made shortly before the next Xcode
    /// "Run" could be silently lost even though the sheet showed success and dismissed.
    /// Root-caused 2026-09-16 after a user-reported case of an edit reverting after a rebuild.
    func save(instance: Instance, in modelContext: ModelContext) async -> Bool {
        errorMessage = nil
        isTesting = true
        defer { isTesting = false }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespaces)
        let newKeyToStore = trimmedKey.isEmpty ? nil : trimmedKey

        let (primaryStore, secondaryStore) = KeyStoreSelection.currentStores()

        do {
            let existingCredential = try credentialResolver.credential(for: instance)
            let effectiveAPIKey = newKeyToStore ?? existingCredential.apiKey

            try await setupService.updateInstance(
                for: instance,
                name: name.trimmingCharacters(in: .whitespaces),
                baseURL: baseURL.trimmingCharacters(in: .whitespaces),
                apiKey: effectiveAPIKey,
                newAPIKeyToStore: newKeyToStore,
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
