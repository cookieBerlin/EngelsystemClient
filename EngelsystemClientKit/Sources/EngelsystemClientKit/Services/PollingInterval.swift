import Foundation

/// How often Shifts/News/Profile refresh themselves in the background, without the
/// user opening a screen or pulling to refresh — see `AppSyncCoordinator` and the iOS
/// app target's `BackgroundSyncScheduler`. `.manual` means "never automatically";
/// background sync is simply left unscheduled in that case.
///
/// 2026-09-22, user-requested, to reduce server load: replaces syncing every time a
/// screen is opened with an interval the user controls, stored on `SyncSettings` (a
/// CloudKit-synced singleton) so the choice is shared between iPhone and Watch.
///
/// **Presets, not free-form minutes, and none below 15**: `BGAppRefreshTask`'s
/// `earliestBeginDate` is only a lower bound — iOS decides the real cadence based on
/// app usage, battery, and system load, and in practice essentially never honors
/// anything shorter than ~15 minutes regardless of what's requested. Offering a
/// 5-minute option would just promise a precision the platform can't deliver; see
/// CLAUDE.md for the fuller writeup.
public enum PollingInterval: Int, CaseIterable, Identifiable, Sendable {
    case manual = 0
    case minutes15 = 15
    case minutes30 = 30
    case minutes60 = 60
    case minutes180 = 180
    case minutes360 = 360

    public var id: Int { rawValue }

    public init(minutes: Int) {
        self = PollingInterval(rawValue: minutes) ?? .manual
    }

    /// "At least every X" rather than "every X" — the wording itself sets the right
    /// expectation up front, rather than relying on a separate footer alone.
    public var title: String {
        switch self {
        case .manual: return "Manual"
        case .minutes15: return "At least every 15 min"
        case .minutes30: return "At least every 30 min"
        case .minutes60: return "At least every hour"
        case .minutes180: return "At least every 3 hours"
        case .minutes360: return "At least every 6 hours"
        }
    }

    public var isManual: Bool { self == .manual }

    /// `nil` for `.manual` — callers use this directly as "should anything be
    /// scheduled at all".
    public var timeInterval: TimeInterval? {
        isManual ? nil : TimeInterval(rawValue * 60)
    }
}
