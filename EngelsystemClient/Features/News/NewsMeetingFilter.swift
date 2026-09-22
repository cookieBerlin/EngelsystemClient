import Foundation
import EngelsystemClientKit

/// Filters `NewsView`'s list by `CachedNews.isMeeting` (2026-09-22, user-requested).
/// Session-scoped (`@State`, not `@AppStorage`) — unlike `MultiInstanceDisplayMode`,
/// this isn't a standing preference about how data is organized, it's closer to a
/// transient list filter (like Mail's), so it resets to `.all` on next launch rather
/// than being remembered.
enum NewsMeetingFilter: String, CaseIterable, Identifiable {
    case all
    case meetingsOnly
    case nonMeetingsOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .meetingsOnly: return "Meetings"
        case .nonMeetingsOnly: return "Non-Meetings"
        }
    }

    func matches(_ item: CachedNews) -> Bool {
        switch self {
        case .all: return true
        case .meetingsOnly: return item.isMeeting
        case .nonMeetingsOnly: return !item.isMeeting
        }
    }
}
