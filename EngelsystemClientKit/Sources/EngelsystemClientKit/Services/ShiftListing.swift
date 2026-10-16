import Foundation

/// Which shifts the Shifts screen lists (menu "Show"). Remembered per device.
public enum ShiftTimeFilter: String, CaseIterable, Identifiable, Sendable {
    /// Running shifts and those that have not begun yet (everything that is not over).
    case upcoming
    /// Shifts that run or begin today, also one that began yesterday and is still going.
    case today
    /// Shifts that are over.
    case past
    case all

    public static let `default` = ShiftTimeFilter.upcoming

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .upcoming: return "Upcoming"
        case .today: return "Today"
        case .past: return "Past"
        case .all: return "All"
        }
    }

    public func matches(startsAt: Date, endsAt: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        switch self {
        case .all:
            return true
        case .upcoming:
            return endsAt >= now
        case .past:
            return endsAt < now
        case .today:
            let dayStart = calendar.startOfDay(for: now)
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return false }
            return startsAt < dayEnd && (endsAt > dayStart || startsAt == dayStart)
        }
    }
}

/// The order of the Shifts screen (menu "Sort"): of the days and of the shifts within a day.
public enum ShiftSortOrder: String, CaseIterable, Identifiable, Sendable {
    case earliestFirst
    case latestFirst

    public static let `default` = ShiftSortOrder.earliestFirst

    public var id: String { rawValue }

    public var title: String {
        self == .earliestFirst ? "Earliest First" : "Latest First"
    }
}

public extension CachedShift {
    func matches(_ filter: ShiftTimeFilter, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        filter.matches(startsAt: startsAt, endsAt: endsAt, now: now, calendar: calendar)
    }

    /// The shifts a filter lets through, in no particular order.
    static func filtered(_ shifts: [CachedShift], by filter: ShiftTimeFilter, now: Date = Date(), calendar: Calendar = .current) -> [CachedShift] {
        shifts.filter { $0.matches(filter, now: now, calendar: calendar) }
    }

    /// Like `groupedByDay(_:calendar:)`, in the chosen order (days and the shifts within a day).
    static func groupedByDay(
        _ shifts: [CachedShift], order: ShiftSortOrder, calendar: Calendar = .current
    ) -> [(day: Date, shifts: [CachedShift])] {
        let groups = groupedByDay(shifts, calendar: calendar)
        guard order == .latestFirst else { return groups }
        return groups.reversed().map { (day: $0.day, shifts: $0.shifts.reversed()) }
    }
}

/// What the Shifts screen shows when the filter hides everything.
public enum ShiftListing {
    /// The filter is the reason for an empty list (shifts exist, but none matches).
    public static func filterHidesEverything(allCount: Int, shownCount: Int) -> Bool {
        allCount > 0 && shownCount == 0
    }
}
