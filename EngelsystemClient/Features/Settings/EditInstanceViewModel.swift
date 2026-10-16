import Foundation
import SwiftData
import EngelsystemClientKit

/// Backs the editable instance page (name, server URL, API key on the page itself; 2026-10-16 — it replaced the
/// separate "Edit Instance" sheet). The API key field is left blank on open (never pre-filled) and blank means
/// "keep the saved key". Nothing is applied until **Save**; **Discard** resets the fields. Saving does not need a
/// successful connection test (the server may be unreachable right now); "Test Connection" is an optional check.
/// Activating the instance and its color are separate, instant actions on the page.
@Observable
@MainActor
final class EditInstanceViewModel {
    var name: String
    var baseURL: String {
        didSet { connectionTested = false }
    }
    var apiKey: String = "" {
        didSet { connectionTested = false }
    }
    var isTesting = false
    var errorMessage: String?
    /// "5 of 8 features available" after a successful `testConnection`; nil otherwise. Never an error.
    var featureSummary: String?

    /// Only drives the "Test Connection" row (progress / checkmark / label); reset whenever the address or key
    /// change, because the result then no longer describes what is in the form.
    var connectionTested = false

    private let apiClient: APIClient
    private let setupService: InstanceSetupService
    private let credentialResolver: InstanceCredentialResolver
    private let capabilities: ServerCapabilities
    private let keyStores: () -> (primary: APIKeyStore, secondary: APIKeyStore)

    init(
        instance: Instance,
        apiClient: APIClient = .shared,
        setupService: InstanceSetupService = InstanceSetupService(),
        credentialResolver: InstanceCredentialResolver = InstanceCredentialResolver(),
        capabilities: ServerCapabilities = .shared,
        keyStores: @escaping () -> (primary: APIKeyStore, secondary: APIKeyStore) = KeyStoreSelection.currentStores
    ) {
        self.capabilities = capabilities
        self.keyStores = keyStores
        self.name = instance.name
        self.baseURL = instance.normalizedBaseURL
        self.apiClient = apiClient
        self.setupService = setupService
        self.credentialResolver = credentialResolver
    }

    /// A demo address needs no key: the field is greyed out with a hint.
    var requiresAPIKey: Bool { InstanceForm.requiresAPIKey(address: baseURL) }

    func hasChanges(for instance: Instance) -> Bool {
        InstanceForm.hasChanges(
            savedName: instance.name, savedAddress: instance.normalizedBaseURL,
            name: name, address: baseURL, typedKey: requiresAPIKey ? apiKey : "")
    }

    var canSave: Bool {
        InstanceForm.canSave(name: name, address: baseURL) && !isTesting
    }

    var canTest: Bool {
        !baseURL.trimmingCharacters(in: .whitespaces).isEmpty && !isTesting
    }

    /// Puts the fields back to the saved instance.
    func discard(to instance: Instance) {
        name = instance.name
        baseURL = instance.normalizedBaseURL
        apiKey = ""
        errorMessage = nil
        featureSummary = nil
        connectionTested = false
    }

    /// Checks the server and key currently in the form (the saved key when the key field is blank) without
    /// saving anything.
    func testConnection(for instance: Instance) async {
        errorMessage = nil
        featureSummary = nil
        isTesting = true
        defer { isTesting = false }

        do {
            let address = baseURL.trimmingCharacters(in: .whitespaces)
            let typedKey = apiKey.trimmingCharacters(in: .whitespaces)
            let key: String
            if !requiresAPIKey {
                key = InstanceForm.demoAPIKey
            } else if typedKey.isEmpty {
                key = try credentialResolver.credential(for: instance).apiKey
            } else {
                key = typedKey
            }
            let credential = EventCredential(baseURL: Instance.apiBasePath(for: address), apiKey: key)
            _ = try await apiClient.fetchInfo(credential)
            let privileges = await apiClient.ownPrivileges(credential)
            featureSummary = ServerCapabilities.featureSummary(privileges: privileges)
            // The same findings feed the instance's Features list, as long as it is still the same server,
            // and then the summary reads that list — so both always say the same.
            if credential.baseURL == Instance.apiBasePath(for: instance.normalizedBaseURL) {
                if let privileges { capabilities.applyPrivileges(privileges, for: instance.id) }
                if let shifts = try? await apiClient.fetchShifts(credential) {
                    capabilities.recordShiftFields(of: shifts, for: instance.id)
                }
                // A demo address has no server to ask: what the demo offers is known.
                if instance.isDemo { capabilities.recordDemoInstance(instance.id, newsOnly: instance.isNewsOnlyDemo) }
                // Without privileges a real server tells nothing about the account: no summary is claimed.
                if privileges != nil || instance.isDemo { featureSummary = capabilities.summaryText(for: instance.id) }
            }
            connectionTested = true
        } catch {
            connectionTested = false
            errorMessage = SyncErrorMapper.message(for: error)
        }
    }

    /// Applies name, address and a freshly typed key to `instance` and persists the context. Does not test the
    /// connection. The explicit `modelContext.save()` matters: SwiftData's autosave only fires on certain
    /// app-lifecycle events, which a debug rebuild-and-relaunch from Xcode skips entirely (root-caused
    /// 2026-09-16 after an edit reverted after a rebuild). Returns whether the server or the key changed, so the
    /// caller can refresh the instance; nil when saving failed.
    func save(instance: Instance, in modelContext: ModelContext) -> Bool? {
        errorMessage = nil
        let typedKey = apiKey.trimmingCharacters(in: .whitespaces)
        let newKeyToStore = requiresAPIKey ? (typedKey.isEmpty ? nil : typedKey) : InstanceForm.demoAPIKey
        let newAddress = baseURL.trimmingCharacters(in: .whitespaces)
        let serverChanged = Instance.normalizedBaseURL(newAddress) != instance.normalizedBaseURL || !typedKey.isEmpty
        let (primaryStore, secondaryStore) = keyStores()

        do {
            try setupService.applyChanges(
                to: instance, name: name.trimmingCharacters(in: .whitespaces), baseURL: newAddress,
                newAPIKeyToStore: newKeyToStore, store: primaryStore)
            // Which store (iCloud vs. local) the key originally landed in isn't tracked on `Instance`, so
            // mirror a freshly typed key into both — otherwise a stale value could linger in whichever store
            // `InstanceCredentialResolver` checks first.
            if let newKeyToStore {
                try? secondaryStore.save(apiKey: newKeyToStore, for: instance.apiKeyKeychainRef)
            }
            try? modelContext.save()
            apiKey = ""
            connectionTested = false
            return serverChanged
        } catch {
            errorMessage = SyncErrorMapper.message(for: error)
            return nil
        }
    }
}
