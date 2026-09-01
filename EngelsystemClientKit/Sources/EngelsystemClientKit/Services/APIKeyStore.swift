import Foundation

/// Shared interface for `KeychainSyncStore` (iCloud) and `LocalKeychainStore`
/// (device-local fallback), so callers don't need to know which of the two
/// stores is currently active.
public protocol APIKeyStore {
    func save(apiKey: String, for reference: String) throws
    func loadAPIKey(for reference: String) throws -> String
    func deleteAPIKey(for reference: String) throws
}

public enum KeychainError: Error {
    case unexpectedStatus(OSStatus)
    case unexpectedData
}

/// Checks whether iCloud is available on the device — the basis for the startup
/// check specified in CLAUDE.md, deciding whether `KeychainSyncStore` can be used
/// or whether to fall back to `LocalKeychainStore` (manual entry).
public enum ICloudAvailability {
    public static var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }
}
