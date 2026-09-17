import Foundation
import SwiftData

/// Builds the shared `ModelContainer` used by both the iOS and Watch app targets, per
/// CLAUDE.md's Sync strategy: `Instance` lives in a CloudKit-backed configuration (same
/// container identifier on both platforms, so instance metadata syncs between them),
/// while the `Cached*` model types the caller passes in stay in a local-only
/// configuration — they're just a per-device cache of API data that gets re-fetched on
/// every sync anyway, so there's no reason to sync them and no way to (SwiftData
/// relationships can't cross `ModelConfiguration`s, which is also why `Instance` no
/// longer has relationships to the `Cached*` types — see `Instance.swift`).
///
/// Falls back to a local-only configuration for `Instance` too when iCloud isn't
/// available on the device (`ICloudAvailability.isAvailable`) — the existing manual
/// entry forms (`InstanceSetupView`, `WatchSetupView`) already cover that case, per the
/// "Fallback" bullet in CLAUDE.md's Sync strategy.
public enum ModelContainerFactory {
    public static let cloudKitContainerIdentifier = "iCloud.net.cuccato.engelsystem.de"

    /// - Parameters:
    ///   - localSchemaTypes: the `Cached*` types this app target uses (iOS: all five;
    ///     Watch: just `CachedShift`, per its excluded-schema design).
    ///   - isStoredInMemoryOnly: `false` for real app use (the default); tests pass
    ///     `true` for an ephemeral container with no on-disk side effects.
    ///   - forceLocalOnly: bypasses the `ICloudAvailability.isAvailable` check and
    ///     always uses a local-only configuration for `Instance` too. Real app code
    ///     never needs this (the availability check already does the right thing);
    ///     it exists so tests get a deterministic container regardless of whether the
    ///     machine running them happens to be signed into iCloud — CloudKit mirroring
    ///     also isn't supported on an in-memory store, so this must be forced whenever
    ///     `isStoredInMemoryOnly` is `true`.
    public static func makeContainer(
        localSchemaTypes: [any PersistentModel.Type],
        isStoredInMemoryOnly: Bool = false,
        forceLocalOnly: Bool = false
    ) -> ModelContainer {
        let cloudSchema = Schema([Instance.self])
        let localSchema = Schema(localSchemaTypes)
        let fullSchema = Schema([Instance.self] + localSchemaTypes)

        let iCloudAvailable = !forceLocalOnly && ICloudAvailability.isAvailable
        // Diagnostic: whether Instance is CloudKit-backed at all is otherwise invisible
        // from the outside — a device with no iCloud account signed in (or one that
        // just never got FileManager.ubiquityIdentityToken populated yet) silently
        // falls back to a fully local, unsynced Instance store, which looks identical
        // to "sync is broken" from the UI (an empty instance list) but has a completely
        // different fix (sign into iCloud on *this* device, separately from any other).
        print("[ModelContainerFactory] ICloudAvailability.isAvailable = \(ICloudAvailability.isAvailable), forceLocalOnly = \(forceLocalOnly) -> Instance is \(iCloudAvailable ? "CloudKit-backed" : "local-only, NOT syncing")")
        if !forceLocalOnly {
            ICloudAvailability.logCloudKitAccountStatus(containerIdentifier: cloudKitContainerIdentifier)
        }
        let cloudKitDatabase: ModelConfiguration.CloudKitDatabase = iCloudAvailable
            ? .private(cloudKitContainerIdentifier)
            : .none

        let cloudConfiguration = ModelConfiguration(
            "Cloud",
            schema: cloudSchema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            cloudKitDatabase: cloudKitDatabase
        )
        let localConfiguration = ModelConfiguration(
            "Local",
            schema: localSchema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: fullSchema, configurations: [cloudConfiguration, localConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
}
