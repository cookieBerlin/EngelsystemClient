import Foundation
import SwiftData
import EngelsystemClientKit

/// Watch equivalent of the iOS app's `EditInstanceViewModel` (`Features/Settings`) — duplicated rather than shared
/// because that type lives in the iOS app target, not `EngelsystemClientKit`. Backs the editable instance page
/// (2026-10-16): the fields are edited in place, **Save** applies them (no successful test needed), **Discard**
/// resets them. Simpler than the iOS version: the Watch always uses its own local keychain entry, independent of
/// iCloud sync (same simplification `WatchSetupViewModel` makes), so there is no store mirroring.
@Observable
@MainActor
final class WatchEditInstanceViewModel {
    var name: String
    var baseURL: String {
        didSet { connectionTested = false }
    }
    /// Left blank on open; blank on save means "keep the existing key" — see the iOS
    /// `EditInstanceViewModel`'s matching field for the full rationale.
    var apiKey: String = "" {
        didSet { connectionTested = false }
    }
    var isTesting = false
    var errorMessage: String?
    /// "5 of 8 features available" after a successful `testConnection`; nil otherwise. Never an error.
    var featureSummary: String?

    /// Only drives the "Test Connection" row; reset when the address or key change.
    var connectionTested = false

    private let apiClient: APIClient
    private let setupService: InstanceSetupService
    private let credentialResolver: InstanceCredentialResolver
    private let keyStore: APIKeyStore

    init(
        instance: Instance,
        apiClient: APIClient = .shared,
        setupService: InstanceSetupService = InstanceSetupService(),
        credentialResolver: InstanceCredentialResolver = InstanceCredentialResolver(),
        keyStore: APIKeyStore = LocalKeychainStore()
    ) {
        self.name = instance.name
        self.baseURL = instance.normalizedBaseURL
        self.apiClient = apiClient
        self.setupService = setupService
        self.credentialResolver = credentialResolver
        self.keyStore = keyStore
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

    /// Checks the server and key in the form (the saved key when the field is blank) without saving anything.
    func testConnection(for instance: Instance) async {
        errorMessage = nil
        featureSummary = nil
        isTesting = true
        defer { isTesting = false }

        do {
            let typedKey = apiKey.trimmingCharacters(in: .whitespaces)
            let key: String
            if !requiresAPIKey {
                key = InstanceForm.demoAPIKey
            } else if typedKey.isEmpty {
                key = try credentialResolver.credential(for: instance).apiKey
            } else {
                key = typedKey
            }
            let address = baseURL.trimmingCharacters(in: .whitespaces)
            let credential = EventCredential(baseURL: Instance.apiBasePath(for: address), apiKey: key)
            _ = try await apiClient.fetchInfo(credential)
            if address.hasPrefix(DemoScenario.scheme) {
                featureSummary = ServerCapabilities.demoSummaryText(newsOnly: DemoScenario.isNewsOnly(address: address))
            } else {
                featureSummary = ServerCapabilities.featureSummary(privileges: await apiClient.ownPrivileges(credential))
            }
            connectionTested = true
        } catch {
            connectionTested = false
            errorMessage = Self.message(for: error)
        }
    }

    /// Applies the edited fields and persists the context (explicit `modelContext.save()`, see the iOS
    /// `EditInstanceViewModel.save`: 2026-09-16 root cause). Does not test the connection. Returns whether the
    /// server or the key changed (the caller then refreshes the instance); nil when saving failed.
    func save(instance: Instance, in modelContext: ModelContext) -> Bool? {
        errorMessage = nil
        let typedKey = apiKey.trimmingCharacters(in: .whitespaces)
        let newKeyToStore = requiresAPIKey ? (typedKey.isEmpty ? nil : typedKey) : InstanceForm.demoAPIKey
        let newAddress = baseURL.trimmingCharacters(in: .whitespaces)
        let serverChanged = Instance.normalizedBaseURL(newAddress) != instance.normalizedBaseURL || !typedKey.isEmpty

        do {
            try setupService.applyChanges(
                to: instance, name: name.trimmingCharacters(in: .whitespaces), baseURL: newAddress,
                newAPIKeyToStore: newKeyToStore, store: keyStore)
            try? modelContext.save()
            apiKey = ""
            connectionTested = false
            return serverChanged
        } catch {
            errorMessage = Self.message(for: error)
            return nil
        }
    }

    static func message(for error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.userMessage
        }
        if error is InstanceCredentialError {
            return "No API key found. Update the API key first."
        }
        return error.localizedDescription
    }
}
