import Foundation
import EngelsystemClientKit

/// Watch equivalent of the iOS app's `UpdateAPIKeyViewModel` (`Features/Settings`) —
/// duplicated rather than shared because that type lives in the iOS app target, not
/// `EngelsystemClientKit`. Simpler than the iOS version: the Watch always uses its own
/// local keychain entry, independent of iCloud sync (same simplification
/// `WatchSetupViewModel` already makes), so there's no primary/secondary store mirroring.
@Observable
@MainActor
final class WatchUpdateAPIKeyViewModel {
    var apiKey: String = ""
    var isTesting = false
    var errorMessage: String?

    private let setupService: InstanceSetupService

    init(setupService: InstanceSetupService = InstanceSetupService()) {
        self.setupService = setupService
    }

    var canSubmit: Bool {
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty && !isTesting
    }

    func update(instance: Instance) async -> Bool {
        errorMessage = nil
        isTesting = true
        defer { isTesting = false }

        do {
            try await setupService.updateAPIKey(for: instance, apiKey: apiKey, store: LocalKeychainStore())
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
        if error is KeychainError {
            return "Could not save the API key to the keychain."
        }
        return error.localizedDescription
    }
}
