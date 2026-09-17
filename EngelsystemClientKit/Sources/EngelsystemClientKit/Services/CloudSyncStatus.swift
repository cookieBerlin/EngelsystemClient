import CloudKit
import Foundation

/// User-facing summary of whether `Instance` can currently sync via CloudKit — shown at
/// the bottom of Settings (iOS + Watch) so a real, on-device sync problem (no iCloud
/// account, restricted by Screen Time/MDM, temporarily down) is visible without digging
/// through console logs. Root-caused 2026-09-18 (see CLAUDE.md's CloudKit sync section):
/// this app previously had no way to tell "sync is fine, just hasn't happened yet" apart
/// from "sync is broken on this device" other than reading `print` output, which is what
/// let `Instance` silently stay local-only on every device for two days.
public enum CloudSyncStatus: Equatable {
    case checking
    case active
    case noAccount
    case restricted
    case temporarilyUnavailable
    case unknown
    case error(String)

    public var displayText: String {
        switch self {
        case .checking: return "Checking iCloud Sync…"
        case .active: return "iCloud Sync: Active"
        case .noAccount: return "iCloud Sync: No iCloud Account"
        case .restricted: return "iCloud Sync: Restricted"
        case .temporarilyUnavailable: return "iCloud Sync: Temporarily Unavailable"
        case .unknown: return "iCloud Sync: Unknown"
        case .error(let message): return "iCloud Sync: Error (\(message))"
        }
    }

    /// Queries `CKContainer.accountStatus()` — CloudKit's own, documented-correct
    /// availability check (unlike `FileManager.ubiquityIdentityToken`, which belongs to
    /// a different iCloud subsystem entirely — see `ICloudAvailability`).
    public static func current(containerIdentifier: String) async -> CloudSyncStatus {
        do {
            let status = try await CKContainer(identifier: containerIdentifier).accountStatus()
            switch status {
            case .available: return .active
            case .noAccount: return .noAccount
            case .restricted: return .restricted
            case .temporarilyUnavailable: return .temporarilyUnavailable
            case .couldNotDetermine: return .unknown
            @unknown default: return .unknown
            }
        } catch {
            return .error(error.localizedDescription)
        }
    }
}
