import Foundation

/// How Shifts/News/Profile render data aggregated across every active instance
/// (2026-09-17 multi-active-instance redesign, CLAUDE.md — any number of instances can
/// be active simultaneously). User-selectable in `SettingsView`, iOS-only: the Watch has
/// no full Shifts/News/Profile catalog screens for this to apply to, only the single
/// "next shift" (see `NextShiftViewModel`), so it isn't mirrored to `WatchSettingsView`.
enum MultiInstanceDisplayMode: String, CaseIterable, Identifiable {
    /// One flat list, sorted as usual, each row labeled with its instance.
    case merged
    /// Exactly one active instance's data shown at a time, switchable via a segmented
    /// control at the top of the screen.
    case switcher
    /// One list per screen, grouped into a section per active instance.
    case sectioned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .merged: return "Merged"
        case .switcher: return "Switcher"
        case .sectioned: return "Sectioned"
        }
    }

    static let userDefaultsKey = "multiInstanceDisplayMode"

    /// The stored raw value as a mode; anything unrecognized falls back to `.merged`.
    static func stored(raw: String) -> MultiInstanceDisplayMode {
        MultiInstanceDisplayMode(rawValue: raw) ?? .merged
    }
}
