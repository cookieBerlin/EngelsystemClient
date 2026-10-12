import CloudKit

/// Thin adapter over the real `CKContainer` — kept in its own file because a test
/// process has no CloudKit entitlements, so this one line can't run in unit tests.
/// Everything that uses it takes it as an injectable closure (see
/// `ICloudAvailability.logCloudKitAccountStatus`). Proposed as a coverage-gate
/// exclusion, pending owner approval (`docs/backlog.md`, C-04).
public enum SystemCloudKitAccount {
    @Sendable public static func accountStatus(containerIdentifier: String) async throws -> CKAccountStatus {
        try await CKContainer(identifier: containerIdentifier).accountStatus()
    }
}

public extension CloudSyncStatus {
    static func current(containerIdentifier: String) async -> CloudSyncStatus {
        await current(containerIdentifier: containerIdentifier, accountStatus: SystemCloudKitAccount.accountStatus(containerIdentifier:))
    }
}
