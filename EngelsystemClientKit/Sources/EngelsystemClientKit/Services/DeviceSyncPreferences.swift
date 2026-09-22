import Foundation

/// Per-device (not CloudKit-synced) sync preferences and diagnostics.
///
/// 2026-09-22, user-requested, part of the polling-interval/background-sync feature.
/// **The polling interval itself was originally a CloudKit-synced `SyncSettings`
/// singleton, shared with the Apple Watch — reverted the same day, at the user's
/// explicit request**: since Watch background execution isn't implemented at all
/// (see CLAUDE.md — `BackgroundTasks` isn't available on watchOS), syncing and
/// displaying an interval that does nothing there was pointless. It's a plain
/// per-device preference now, exactly like "sync on app start" and "last background
/// sync" always were — `WatchSettingsView` doesn't show it at all any more.
public enum DeviceSyncPreferences {
    public static let syncOnAppStartUserDefaultsKey = "syncOnAppStartEnabled"
    public static let pollingIntervalUserDefaultsKey = "pollingIntervalMinutes"
    private static let lastBackgroundSyncUserDefaultsKey = "lastBackgroundSyncAt"

    /// Defaults to on, matching today's perceived behavior on a cold launch.
    public static func syncOnAppStartEnabled(in defaults: UserDefaults = .standard) -> Bool {
        (defaults.object(forKey: syncOnAppStartUserDefaultsKey) as? Bool) ?? true
    }

    /// `UserDefaults.integer(forKey:)` returns `0` for an unset key, which
    /// `PollingInterval(minutes:)` already maps to `.manual` — the correct default,
    /// so no extra "has this ever been set" check is needed here.
    public static func pollingInterval(in defaults: UserDefaults = .standard) -> PollingInterval {
        PollingInterval(minutes: defaults.integer(forKey: pollingIntervalUserDefaultsKey))
    }

    /// Recorded whenever the background task actually runs, regardless of whether
    /// every instance synced cleanly — this reflects "did a background sync happen",
    /// not "did it fully succeed", so the Settings footer stays meaningful even when
    /// one instance is temporarily unreachable.
    public static func recordBackgroundSync(at date: Date = Date(), in defaults: UserDefaults = .standard) {
        defaults.set(date, forKey: lastBackgroundSyncUserDefaultsKey)
    }

    public static func lastBackgroundSyncDate(in defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: lastBackgroundSyncUserDefaultsKey) as? Date
    }
}
