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
    var baseURL: String
    /// Fallback for servers that 404 on the `self` path-parameter alias — see
    /// `Instance.userID`. Kept as text here since it's an optional numeric field on a
    /// form; parsed on submit.
    var userIDText: String
    /// Left blank on open; blank on save means "keep the existing key" — see the iOS
    /// `EditInstanceViewModel`'s matching field for the full rationale.
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
                userID: Int(userIDText.trimmingCharacters(in: .whitespaces)),
                store: store
            )
            try? modelContext.save()
            return true
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    private static func message(for error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.userMessage
        }
        if error is InstanceCredentialError {
            return "No API key found. Update the API key first."
        }
        return error.localizedDescription
    }
}
