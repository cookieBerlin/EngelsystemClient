import Foundation
import EngelsystemClientKit

/// The short, secondary text on each row of the Settings hub (2026-10-13). Pure functions
/// of the stored values, so the wording is unit-tested.
enum SettingsSummary {
    static func instances(active: Int, total: Int) -> String {
        total == 0 ? "None" : "\(active) of \(total) active"
    }

    /// The reminder lead times of this device, ascending, e.g. "15, 30 min"; "Off" without any.
    static func notifications(leadTimes: [Int]) -> String {
        leadTimes.isEmpty ? "Off" : leadTimes.sorted().map(String.init).joined(separator: ", ") + " min"
    }

    static func sync(pollingIntervalMinutes: Int) -> String {
        PollingInterval(minutes: pollingIntervalMinutes).title
    }

    static func privacy(mapLinkRaw: String) -> String {
        MapLinkMode.stored(raw: mapLinkRaw) == .embedded ? "Embedded map" : "Link only"
    }

    static func diagnostics(isEnabled: Bool) -> String {
        isEnabled ? "Logging on" : "Logging off"
    }

    /// The marketing version from the bundle's Info dictionary, e.g. "0.1.0".
    static func version(info: [String: Any]?) -> String {
        info?["CFBundleShortVersionString"] as? String ?? ""
    }
}
