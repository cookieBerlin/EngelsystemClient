import Foundation
import Testing
@testable import EngelsystemClientKit

struct ShiftListingTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 12, day: day, hour: hour, minute: minute))!
    }

    private func shift(_ id: Int, from start: Date, to end: Date) -> CachedShift {
        CachedShift(serverID: id, instanceID: UUID(), title: "S\(id)", startsAt: start, endsAt: end,
                    locationID: 1, shiftTypeID: 1, url: "https://x.test/\(id)")
    }

    private var now: Date { date(10, 14) } // 10 Dec 2026, 14:00

    @Test func upcomingKeepsRunningAndFutureShifts() {
        let filter = ShiftTimeFilter.upcoming
        #expect(filter.matches(startsAt: date(10, 12), endsAt: date(10, 16), now: now, calendar: calendar)) // running
        #expect(filter.matches(startsAt: date(10, 18), endsAt: date(10, 20), now: now, calendar: calendar))
        #expect(filter.matches(startsAt: date(10, 12), endsAt: now, now: now, calendar: calendar)) // ends right now
        #expect(!filter.matches(startsAt: date(10, 8), endsAt: date(10, 12), now: now, calendar: calendar))
    }

    @Test func pastKeepsOnlyFinishedShifts() {
        let filter = ShiftTimeFilter.past
        #expect(filter.matches(startsAt: date(9, 8), endsAt: date(9, 12), now: now, calendar: calendar))
        #expect(!filter.matches(startsAt: date(10, 12), endsAt: now, now: now, calendar: calendar))
        #expect(!filter.matches(startsAt: date(10, 12), endsAt: date(10, 16), now: now, calendar: calendar))
    }

    @Test func todayCoversEverythingThatTouchesTheDay() {
        let filter = ShiftTimeFilter.today
        func matches(_ start: Date, _ end: Date) -> Bool { filter.matches(startsAt: start, endsAt: end, now: now, calendar: calendar) }
        #expect(matches(date(10, 6), date(10, 8))) // earlier today, already over
        #expect(matches(date(10, 22), date(11, 2))) // begins today, ends tomorrow
        #expect(matches(date(9, 22), date(10, 2))) // began yesterday, still going into today
        #expect(matches(date(10, 0), date(10, 0))) // zero-length at midnight
        #expect(!matches(date(9, 22), date(10, 0))) // ended exactly at midnight: yesterday's
        #expect(!matches(date(11, 0), date(11, 4))) // begins exactly at tomorrow's midnight
        #expect(!matches(date(8, 8), date(8, 12)))
    }

    @Test func allLetsEverythingThrough() {
        #expect(ShiftTimeFilter.all.matches(startsAt: date(1, 8), endsAt: date(1, 9), now: now, calendar: calendar))
        #expect(ShiftTimeFilter.allCases.map(\.title) == ["Upcoming", "Today", "Past", "All"])
        #expect(ShiftTimeFilter.default == .upcoming)
        #expect(ShiftTimeFilter.past.id == "past")
    }

    @Test func filteringWorksOnCachedShifts() {
        let past = shift(1, from: date(9, 8), to: date(9, 12))
        let running = shift(2, from: date(10, 12), to: date(10, 16))
        let future = shift(3, from: date(12, 8), to: date(12, 12))
        let all = [past, running, future]
        #expect(CachedShift.filtered(all, by: .upcoming, now: now, calendar: calendar).map(\.serverID) == [2, 3])
        #expect(CachedShift.filtered(all, by: .past, now: now, calendar: calendar).map(\.serverID) == [1])
        #expect(CachedShift.filtered(all, by: .today, now: now, calendar: calendar).map(\.serverID) == [2])
        #expect(CachedShift.filtered(all, by: .all, now: now, calendar: calendar).count == 3)
        #expect(running.matches(.today, now: now, calendar: calendar))
    }

    @Test func daysAndShiftsFollowTheChosenOrder() {
        let a = shift(1, from: date(10, 8), to: date(10, 10))
        let b = shift(2, from: date(10, 12), to: date(10, 14))
        let c = shift(3, from: date(11, 9), to: date(11, 11))
        let earliest = CachedShift.groupedByDay([b, c, a], order: .earliestFirst, calendar: calendar)
        #expect(earliest.map { $0.shifts.map(\.serverID) } == [[1, 2], [3]])
        let latest = CachedShift.groupedByDay([b, c, a], order: .latestFirst, calendar: calendar)
        #expect(latest.map { $0.shifts.map(\.serverID) } == [[3], [2, 1]])
        #expect(latest[0].day > latest[1].day)
        #expect(ShiftSortOrder.allCases.map(\.title) == ["Earliest First", "Latest First"])
        #expect(ShiftSortOrder.default == .earliestFirst)
        #expect(ShiftSortOrder.latestFirst.id == "latestFirst")
    }

    @Test func storedRawValuesFallBackToTheDefaults() {
        #expect(ShiftTimeFilter.stored(raw: "past") == .past)
        #expect(ShiftTimeFilter.stored(raw: "nonsense") == .upcoming)
        #expect(ShiftSortOrder.stored(raw: "latestFirst") == .latestFirst)
        #expect(ShiftSortOrder.stored(raw: "") == .earliestFirst)
        #expect(ShiftTimeFilter.userDefaultsKey != ShiftSortOrder.userDefaultsKey)
    }

    @Test func theFilterIsOnlyTheReasonWhenShiftsExistButNoneIsShown() {
        #expect(ShiftListing.filterHidesEverything(allCount: 3, shownCount: 0))
        #expect(!ShiftListing.filterHidesEverything(allCount: 3, shownCount: 1))
        #expect(!ShiftListing.filterHidesEverything(allCount: 0, shownCount: 0))
    }
}
