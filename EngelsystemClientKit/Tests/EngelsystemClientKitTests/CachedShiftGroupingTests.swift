import Foundation
import Testing
@testable import EngelsystemClientKit

/// `ShiftsView` groups shifts by calendar day so the date is visible (a shift row on
/// its own only shows a time) — see `CachedShift.groupedByDay`.
struct CachedShiftGroupingTests {
    private static let calendar = Calendar(identifier: .gregorian)

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private static func shift(id: Int, _ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> CachedShift {
        let start = date(year, month, day, hour)
        return CachedShift(
            serverID: id,
            instanceID: UUID(),
            title: "Shift \(id)",
            startsAt: start,
            endsAt: start.addingTimeInterval(2 * 3600),
            locationID: 1,
            shiftTypeID: 1,
            url: "https://example.org/shifts/\(id)"
        )
    }

    @Test func groupsShiftsByCalendarDayInAscendingOrder() {
        let day1Morning = Self.shift(id: 1, 2026, 9, 15, 9)
        let day1Evening = Self.shift(id: 2, 2026, 9, 15, 18)
        let day2 = Self.shift(id: 3, 2026, 9, 16, 10)

        let grouped = CachedShift.groupedByDay([day2, day1Evening, day1Morning], calendar: Self.calendar)

        #expect(grouped.count == 2)
        #expect(grouped[0].day == Self.calendar.startOfDay(for: day1Morning.startsAt))
        // Within a day, shifts are sorted by start time regardless of input order.
        #expect(grouped[0].shifts.map(\.serverID) == [1, 2])
        #expect(grouped[1].day == Self.calendar.startOfDay(for: day2.startsAt))
        #expect(grouped[1].shifts.map(\.serverID) == [3])
    }

    @Test func emptyInputProducesNoGroups() {
        #expect(CachedShift.groupedByDay([], calendar: Self.calendar).isEmpty)
    }
}
