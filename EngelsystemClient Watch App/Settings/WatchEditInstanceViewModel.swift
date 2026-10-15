import Foundation
import SwiftData
import EngelsystemClientKit

/// Watch equivalent of the iOS app's `EditInstanceViewModel` (`Features/Settings`) —
/// duplicated rather than shared because that type lives in the iOS app target, not
/// `EngelsystemClientKit`. Simpler than the iOS version: the Watch always uses its own
/// local keychain entry, independent of iCloud sync (same simplification
/// `WatchSetupViewModel` already makes), so there's no primary/secondary store
/// mirroring when a new key is entered.
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
    /// "5 of 8 features available" after a successful `testConnection` against a server that
    /// reports the account's privileges (PR #1709); nil otherwise. Never an error.
    var featureSummary: String?

    /// See the iOS `EditInstanceViewModel` counterpart for the full rationale — gates
    /// Save (`canSubmit`) and drives the "Test Connection" button's own display; reset
    /// on `baseURL`/`apiKey` edits, so Save re-enables only after a fresh test.
    var connectionTested = true

    private let apiClient: APIClient
    private let setupService: InstanceSetupService
    private let credentialResolver: InstanceCredentialResolver

    init(
        instance: Instance,
        apiClient: APIClient = .shared,
        setupService: InstanceSetupService = InstanceSetupService(),
        credentialResolver: InstanceCredentialResolver = InstanceCredentialResolver()
    ) {
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

    /// See the iOS `EditInstanceViewModel.testConnection(for:)` counterpart for the
    /// full rationale. Pressing "Test Connection" alone never mutates the store.
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
            featureSummary = ServerCapabilities.featureSummary(privileges: await apiClient.ownPrivileges(credential))
            connectionTested = true
        } catch {
            connectionTested = false
            errorMessage = Self.message(for: error)
        }
    }

    /// Explicit `modelContext.save()` after the mutation — see the matching comment on
    /// iOS's `EditInstanceViewModel.save`, same root cause and fix (2026-09-16).
    func save(instance: Instance, in modelContext: ModelContext) async -> Bool {
        errorMessage = nil
        isTesting = true
        defer { isTesting = false }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespaces)
        let newKeyToStore = trimmedKey.isEmpty ? nil : trimmedKey
        let store = LocalKeychainStore()

        do {
            let existingCredential = try credentialResolver.credential(for: instance)
            let effectiveAPIKey = newKeyToStore ?? existingCredential.apiKey

            try await setupService.updateInstance(
                for: instance,
                name: name.trimmingCharacters(in: .whitespaces),
                baseURL: baseURL.trimmingCharacters(in: .whitespaces),
                apiKey: effectiveAPIKey,
                newAPIKeyToStore: newKeyToStore,
                store: store
            )
            try? modelContext.save()
            return true
        } catch {
            errorMessage = Self.message(for: error)
            return false
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
