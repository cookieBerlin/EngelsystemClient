import Foundation

/// Conformed by every `Cached*` model — each already carries `instanceID` (which
/// instance it came from) and `cachedAt` (set on insert, refreshed by
/// `updateCacheTimestamp()` on every update via `apply(_:)`), so `cachedAt` already
/// *is* "when this item was last synced from the server". This protocol just gives
/// that shared shape a name so `CacheSyncTimestamp.lastSyncDate` can work generically
/// across all five types instead of five near-identical call sites.
public protocol CacheTimestamped {
    var instanceID: UUID { get }
    var cachedAt: Date { get }
}

extension CachedShift: CacheTimestamped {}
extension CachedNews: CacheTimestamped {}
extension CachedUser: CacheTimestamped {}
extension CachedWorklog: CacheTimestamped {}
extension CachedAngelTypeMembership: CacheTimestamped {}
extension CachedLocation: CacheTimestamped {}

/// Backs the "Last Synced" section on the instance detail screens (iOS `SettingsView`,
/// Watch `WatchSettingsView`) — 2026-09-23, user-requested. Each screen already holds
/// an unfiltered `@Query` per `Cached*` type (matching this project's existing pattern
/// of fetching everything and filtering by `instanceID` in Swift, since record counts
/// here are small — see CLAUDE.md's Shifts/News/Profile screens), so this just picks
/// out the freshest `cachedAt` among the rows belonging to one specific instance.
public enum CacheSyncTimestamp {
    /// `nil` when nothing for this instance has ever been cached yet (e.g. it's never
    /// been synced, or was just created).
    public static func lastSyncDate<T: CacheTimestamped>(for instanceID: UUID, in items: [T]) -> Date? {
        items.lazy.filter { $0.instanceID == instanceID }.map(\.cachedAt).max()
    }

    /// For a domain made up of more than one `Cached*` type synced together (Profile:
    /// `CachedUser` + `CachedWorklog` + `CachedAngelTypeMembership`, all refreshed by
    /// the same `ProfileSyncService` pass) — the freshest across all of them stands in
    /// for "when Profile was last synced" as a whole.
    public static func mostRecent(_ dates: [Date?]) -> Date? {
        dates.compactMap { $0 }.max()
    }
}
