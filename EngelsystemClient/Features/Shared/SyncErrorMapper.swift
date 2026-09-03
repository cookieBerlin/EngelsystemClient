import Foundation
import EngelsystemClientKit

/// Shared error-to-message mapping for every feature view model that syncs data
/// via one of the `EngelsystemClientKit` sync services, so the switch over
/// `APIError` cases doesn't get duplicated in Shifts/News/Profile.
enum SyncErrorMapper {
    static func message(for error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.userMessage
        }
        if error is InstanceCredentialError {
            return "No API key found for this instance. Try adding it again in Settings."
        }
        if error is KeychainError {
            return "Could not save the API key to the keychain."
        }
        return error.localizedDescription
    }

    /// True for an expired/revoked API key. Per CLAUDE.md's error-handling contract
    /// ("401 → back to Instance Setup"), Shifts/News/Profile use this to send the user
    /// back to Settings, where "Update API Key" can fix it — adapted from the original
    /// "back to Instance Setup" wording, written before Settings/instance management
    /// existed as its own screen.
    static func isUnauthorized(_ error: Error) -> Bool {
        (error as? APIError) == .unauthorized
    }
}
