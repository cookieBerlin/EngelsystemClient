import Foundation
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
    /// key and, on success, updates `instance` in place.
    func save(instance: Instance) async -> Bool {
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
            return true
        } catch {
            errorMessage = SyncErrorMapper.message(for: error)
            return false
        }
    }
}
