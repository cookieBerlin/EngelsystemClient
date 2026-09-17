import CloudKit
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

    /// Diagnostic only, temporary: `ubiquityIdentityToken` (above, and CLAUDE.md's
    /// originally-specified startup check) belongs to the iCloud Documents/Ubiquity-
    /// container API family — a *different* Apple iCloud subsystem from CloudKit, which
    /// is what `Instance` actually syncs through (see `ModelContainerFactory`). Logs
    /// `CKContainer.accountStatus()` (CloudKit's own, documented-correct availability
    /// check) alongside it, to find out whether `isAvailable` has been checking the
    /// wrong API this whole time — being investigated 2026-09-18 after a real Watch
    /// reported `isAvailable = false` (and so fell back to local-only, unsynced) despite
    /// the correct iCloud account being signed in and iCloud Drive enabled on the
    /// paired iPhone.
    public static func logCloudKitAccountStatus(containerIdentifier: String) {
        Task {
            do {
                let status = try await CKContainer(identifier: containerIdentifier).accountStatus()
                print("[ICloudAvailability] ubiquityIdentityToken != nil = \(isAvailable), CKContainer.accountStatus = \(status)")
            } catch {
                print("[ICloudAvailability] ubiquityIdentityToken != nil = \(isAvailable), CKContainer.accountStatus threw: \(error)")
            }
        }
    }
}
