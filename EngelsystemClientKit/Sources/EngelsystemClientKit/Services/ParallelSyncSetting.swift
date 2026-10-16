import Foundation

/// The per-device "Parallel Syncs" setting: how many instances a full sync handles at the same time.
/// 0 means no limit (all at once), 1 is the former one-after-the-other. iPhone and Watch each keep
/// their own value (`UserDefaults`, not CloudKit) and show it with the same stepper.
public enum ParallelSyncSetting {
    public static let userDefaultsKey = "parallelSyncLimit"
    public static let range = 0...10

    /// Keeps a stored or typed value inside `range`.
    public static func clamp(_ value: Int) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// The device's value; unset is 0 (unlimited).
    public static func stored(in defaults: UserDefaults = .standard) -> Int {
        clamp(defaults.integer(forKey: userDefaultsKey))
    }

    /// "Unlimited", "1 at a time", "3 at a time".
    public static func title(for value: Int) -> String {
        let value = clamp(value)
        return value == 0 ? "Unlimited" : "\(value) at a time"
    }
}
