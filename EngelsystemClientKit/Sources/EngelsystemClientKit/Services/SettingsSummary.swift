import Foundation

/// The short, secondary text on each row of the Settings hub of the iPhone (2026-10-13) and of the Apple Watch
/// (2026-10-16). Pure functions of the stored values, so the wording is unit-tested.
public enum SettingsSummary {
    public static func instances(active: Int, total: Int) -> String {
        total == 0 ? "None" : "\(active) of \(total) active"
    }

    /// The reminder lead times of this device, ascending, e.g. "15, 30 min"; "Off" without any.
    public static func notifications(leadTimes: [Int]) -> String {
        leadTimes.isEmpty ? "Off" : leadTimes.sorted().map(String.init).joined(separator: ", ") + " min"
    }

    public static func sync(pollingIntervalMinutes: Int) -> String {
        PollingInterval(minutes: pollingIntervalMinutes).title
    }

    /// The Watch has no interval, only "sync when the app opens".
    public static func watchSync(onAppStart: Bool) -> String {
        onAppStart ? "On app start" : "Manual"
    }

    public static func diagnostics(isEnabled: Bool) -> String {
        isEnabled ? "Logging on" : "Logging off"
    }

    /// The marketing version from the bundle's Info dictionary, e.g. "0.1.0".
    public static func version(info: [String: Any]?) -> String {
        info?["CFBundleShortVersionString"] as? String ?? ""
    }
}
