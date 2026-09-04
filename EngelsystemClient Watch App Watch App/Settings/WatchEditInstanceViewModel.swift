import Foundation
import EngelsystemClientKit

/// Watch equivalent of the iOS app's `EditInstanceViewModel` (`Features/Settings`) —
/// duplicated rather than shared for the same reason as `WatchUpdateAPIKeyViewModel`
/// (that type lives in the iOS app target, not `EngelsystemClientKit`). Uses
/// `InstanceCredentialResolver` directly rather than `WatchUpdateAPIKeyViewModel`'s
/// always-`LocalKeychainStore` simplification, since the existing API key could in
/// principle live in either store and this needs to *read* it, not write it.
@Observable
@MainActor
final class WatchEditInstanceViewModel {
    var name: String
    var baseURL: String
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
        self.setupService = setupService
        self.credentialResolver = credentialResolver
    }

    var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !isTesting
    }

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
                apiKey: credential.apiKey
            )
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
