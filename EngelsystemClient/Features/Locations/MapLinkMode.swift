import Foundation

/// How a location's map link (`map_url`) is presented in `LocationDetailView`
/// (2026-10-13, user-requested). Per-device `@AppStorage`, iOS-only — Locations does not
/// exist on the Watch. See ADR 0014 for the embedded web view's restrictions.
enum MapLinkMode: String, CaseIterable, Identifiable {
    /// Only the "Show Map" link, which opens the system browser.
    case linkOnly
    /// The link plus the map page rendered inside the screen, loaded fresh every time.
    case embedded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .linkOnly: return "Link Only"
        case .embedded: return "Link and Embedded Map"
        }
    }

    static let userDefaultsKey = "mapLinkMode"

    /// The stored raw value as a mode; anything unrecognized falls back to `.embedded` (the default).
    static func stored(raw: String) -> MapLinkMode {
        MapLinkMode(rawValue: raw) ?? .embedded
    }

    /// Only plain web addresses may be loaded into the embedded view (never `file:`,
    /// `javascript:`, custom app schemes, …).
    static let allowedSchemes = ["http", "https"]

    /// The map address as a URL the embedded view may load, or nil.
    static func embeddableURL(_ string: String?) -> URL? {
        guard let string, let url = URL(string: string), let scheme = url.scheme?.lowercased(),
              allowedSchemes.contains(scheme), url.host?.isEmpty == false else { return nil }
        return url
    }

    /// Whether the embedded view may navigate to `url` (links inside the map page).
    static func allowsNavigation(to url: URL?) -> Bool {
        guard let url else { return false }
        return embeddableURL(url.absoluteString) != nil
    }

    enum NavigationDecision: Equatable { case allow, cancel }

    /// What the embedded view does with a navigation: web addresses stay in the view
    /// (the view additionally keeps iOS from handing them to other apps, see
    /// `EmbeddedMapView`), everything else is cancelled.
    static func navigationDecision(to url: URL?) -> NavigationDecision {
        allowsNavigation(to: url) ? .allow : .cancel
    }
}

/// Automatic deletion of the embedded map's website data every N days (so a consent cookie
/// does not live forever). Per device; 0 means never, `untilAppQuits` keeps it in memory only.
enum MapWebsiteDataRetention {
    static let userDefaultsKey = "mapWebsiteDataAutoDeleteDays"
    static let lastCleanupUserDefaultsKey = "mapWebsiteDataLastCleanup"
    static let defaultDays = 30
    /// Cookies are kept only while the app process lives (in-memory store, gone after a
    /// restart) — stored in the same setting as a negative number of days.
    static let untilAppQuits = -1
    static let choices = [untilAppQuits, 7, 30, 90, 180, 0]

    static func title(days: Int) -> String {
        switch days {
        case untilAppQuits: return "Until the App Quits"
        case 0: return "Never"
        default: return "Every \(days) Days"
        }
    }

    static func keepsDataOnlyInMemory(days: Int) -> Bool { days == untilAppQuits }

    /// Whether the cleanup is due. No earlier cleanup (first use) is never due — the caller
    /// starts the clock instead.
    static func isDue(lastCleanup: Date?, days: Int, now: Date) -> Bool {
        guard days > 0, let lastCleanup else { return false }
        return now.timeIntervalSince(lastCleanup) >= Double(days) * 86_400
    }
}
