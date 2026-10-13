import Foundation
import WebKit

/// The embedded map's own, persistent website data (cookies such as a map provider's
/// consent), kept apart from Safari and from everything else in the app. ADR 0014.
enum MapWebsiteData {
    /// Fixed identifier of the map view's persistent `WKWebsiteDataStore`.
    static let storeIdentifier = UUID(uuidString: "6D4E4C0B-3B4F-4C7A-9C58-0E5A3B1F2A10")!

    @MainActor static var persistentStore: WKWebsiteDataStore { WKWebsiteDataStore(forIdentifier: storeIdentifier) }

    /// One in-memory store for the whole app run ("Until the App Quits"): shared by every
    /// map screen while the process lives, never written to disk.
    @MainActor private static let sessionStore = WKWebsiteDataStore.nonPersistent()

    @MainActor static func store(forAutoDeleteDays days: Int) -> WKWebsiteDataStore {
        MapWebsiteDataRetention.keepsDataOnlyInMemory(days: days) ? sessionStore : persistentStore
    }

    /// Deletes all map website data when the automatic cleanup interval has passed since the
    /// last cleanup (first use only starts the clock). Runs before the map loads.
    @MainActor static func deleteIfDue(days: Int, defaults: UserDefaults = .standard, now: Date = Date()) async {
        let key = MapWebsiteDataRetention.lastCleanupUserDefaultsKey
        let last = defaults.object(forKey: key) as? Date
        if MapWebsiteDataRetention.isDue(lastCleanup: last, days: days, now: now) {
            await deleteAll(now: now)
            defaults.set(now, forKey: key)
        } else if last == nil {
            defaults.set(now, forKey: key)
        }
    }

    /// Deletes everything the map pages stored, in both the persistent and the in-memory store.
    @MainActor static func deleteAll(now: Date = Date()) async {
        for store in [persistentStore, sessionStore] {
            await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        }
        UserDefaults.standard.set(now, forKey: MapWebsiteDataRetention.lastCleanupUserDefaultsKey)
    }
}
