import Foundation
import SwiftData

/// Instance bookkeeping that the Settings screens (iOS and Watch) used to do inline in
/// their views — extracted so it is shared between both and covered by unit tests.
public extension Instance {
    /// Activates/deactivates this instance and saves immediately (no connection test). Returns
    /// whether the instance was just switched **on** — the caller then refreshes it, because its
    /// cache may be old.
    @discardableResult
    func setActive(_ isActive: Bool, in modelContext: ModelContext) -> Bool {
        let wasActive = self.isActive
        self.isActive = isActive
        touch()
        try? modelContext.save()
        return isActive && !wasActive
    }
}

public extension Instance {
    /// Sets the instance's color (nil = Auto) and saves; the color syncs to the other devices via iCloud.
    func setColor(_ color: InstancePalette?, in modelContext: ModelContext) {
        colorKey = color?.rawValue
        touch()
        try? modelContext.save()
    }
}

public extension NotificationLeadTimeSettings {
    /// A platform's reminder lead times, sorted ascending purely for a stable display
    /// order, falling back to the defaults when that platform has no row yet.
    static func leadTimes(for platform: String, in rows: [NotificationLeadTimeSettings]) -> [Int] {
        (rows.first(where: { $0.platform == platform })?.leadTimesMinutes ?? defaultLeadTimesMinutes).sorted()
    }

    /// Adds a reminder lead time for a platform (creating its row if needed); a lead
    /// time that is already present is ignored.
    static func addLeadTime(_ minutes: Int, for platform: String, in modelContext: ModelContext) {
        let settings = resolve(for: platform, in: modelContext)
        guard !settings.leadTimesMinutes.contains(minutes) else { return }
        settings.leadTimesMinutes.append(minutes)
        settings.touch()
        try? modelContext.save()
    }

    static func removeLeadTime(_ minutes: Int, for platform: String, in modelContext: ModelContext) {
        let settings = resolve(for: platform, in: modelContext)
        settings.leadTimesMinutes.removeAll { $0 == minutes }
        settings.touch()
        try? modelContext.save()
    }
}

/// Deletes an `Instance` together with everything that belongs to it.
public enum InstanceRemoval {
    /// Which `Cached*` types exist in the calling app's schema: the iOS app caches all
    /// of them, the Watch app only shifts.
    public enum CacheScope {
        case all
        case shiftsOnly
    }

    /// Removes the API key from every given store (store affiliation — iCloud vs. local —
    /// isn't persisted, so all are tried; a missing entry is a no-op), then deletes the
    /// instance's cached rows (a manual cascade: `Instance` is CloudKit-backed and the
    /// `Cached*` models are local-only, in separate `ModelConfiguration`s, so SwiftData's
    /// relationship cascade doesn't apply across them) and finally the instance itself.
    public static func delete(
        _ instance: Instance,
        in modelContext: ModelContext,
        keyStores: [APIKeyStore],
        scope: CacheScope
    ) {
        for store in keyStores {
            try? store.deleteAPIKey(for: instance.apiKeyKeychainRef)
        }

        let instanceID = instance.id
        try? modelContext.delete(model: CachedShift.self, where: #Predicate { $0.instanceID == instanceID })
        if scope == .all {
            try? modelContext.delete(model: CachedNews.self, where: #Predicate { $0.instanceID == instanceID })
            try? modelContext.delete(model: CachedUser.self, where: #Predicate { $0.instanceID == instanceID })
            try? modelContext.delete(model: CachedWorklog.self, where: #Predicate { $0.instanceID == instanceID })
            try? modelContext.delete(model: CachedAngelTypeMembership.self, where: #Predicate { $0.instanceID == instanceID })
            try? modelContext.delete(model: CachedLocation.self, where: #Predicate { $0.instanceID == instanceID })
        }

        modelContext.delete(instance)
        try? modelContext.save()
    }
}
