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
        return error.localizedDescription
    }
}
