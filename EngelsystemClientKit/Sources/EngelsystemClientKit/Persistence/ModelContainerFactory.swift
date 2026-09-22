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
/// `Instance` is unconditionally CloudKit-backed in production (2026-09-18 — no
/// device-side availability pre-check; see the root-cause comment in
/// `makeContainer` below for why one existed before and why it was wrong)
/// — `forceLocalOnly` exists purely for deterministic, offline tests. The existing
/// manual entry forms (`InstanceSetupView`, `WatchSetupView`) remain the real fallback
/// path per the "Fallback" bullet in CLAUDE.md's Sync strategy, since CloudKit itself
/// still degrades gracefully (local reads/writes keep working) when there's genuinely
/// no iCloud account on the device.
public enum ModelContainerFactory {
    public static let cloudKitContainerIdentifier = "iCloud.net.cuccato.engelsystem.de"

    /// - Parameters:
    ///   - localSchemaTypes: the `Cached*` types this app target uses (iOS: all five;
    ///     Watch: just `CachedShift`, per its excluded-schema design).
    ///   - isStoredInMemoryOnly: `false` for real app use (the default); tests pass
    ///     `true` for an ephemeral container with no on-disk side effects.
    ///   - forceLocalOnly: always uses a local-only configuration for `Instance` too.
    ///     Real app code never needs this; it exists so tests get a deterministic
    ///     container regardless of this machine's iCloud state — CloudKit mirroring
    ///     isn't supported on an in-memory store at all, so this must be forced
    ///     whenever `isStoredInMemoryOnly` is `true`.
    public static func makeContainer(
        localSchemaTypes: [any PersistentModel.Type],
        isStoredInMemoryOnly: Bool = false,
        forceLocalOnly: Bool = false
    ) -> ModelContainer {
        // NotificationLeadTimeSettings (2026-09-22) joins Instance here too — it's
        // CloudKit-synced like Instance, just partitioned by platform (see its own
        // doc comment) rather than being a single cross-platform singleton.
        let cloudSchema = Schema([Instance.self, NotificationLeadTimeSettings.self])
        let localSchema = Schema(localSchemaTypes)
        let fullSchema = Schema([Instance.self, NotificationLeadTimeSettings.self] + localSchemaTypes)

        // Always CloudKit-backed in production — forceLocalOnly is only for tests,
        // which need a fully offline, deterministic container regardless of this
        // machine's iCloud state (CloudKit mirroring isn't supported on an in-memory
        // store at all). Root-caused 2026-09-18: this used to also gate on
        // `ICloudAvailability.isAvailable` (`FileManager.ubiquityIdentityToken != nil`),
        // per CLAUDE.md's originally-specified startup check — but that API belongs to
        // the iCloud Documents/Ubiquity-container family, a *different* Apple iCloud
        // subsystem from CloudKit. Confirmed on a real Watch: `isAvailable` reported
        // `false` while `CKContainer.accountStatus()` correctly reported `.available`
        // for the very same signed-in account — meaning this check silently forced
        // *every* device (very likely the iPhone too, just unnoticed since a
        // single-device install works identically whether or not sync is actually
        // happening) into local-only mode the whole time. `Instance` sync between
        // devices was never actually exercised despite the entitlements being
        // correctly provisioned (see Entitlements in CLAUDE.md). CloudKit's own
        // mirroring already degrades gracefully with no iCloud account at all (the
        // local store keeps working; sync merely pauses until an account becomes
        // available), so there's no need for a synchronous pre-check here at all —
        // removed rather than switched to `CKContainer.accountStatus()`, since that API
        // is async and container creation happens synchronously at app launch.
        let cloudKitDatabase: ModelConfiguration.CloudKitDatabase = forceLocalOnly
            ? .none
            : .private(cloudKitContainerIdentifier)
        print("[ModelContainerFactory] Instance is \(forceLocalOnly ? "local-only (forced, test-only)" : "CloudKit-backed")")
        if !forceLocalOnly {
            ICloudAvailability.logCloudKitAccountStatus(containerIdentifier: cloudKitContainerIdentifier)
        }

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
