import Foundation
import SwiftData
import Testing
@testable import EngelsystemClientKit

/// Pure helpers on the cached models (sorting, grouping, time status, merging) —
/// covered without a `ModelContext` except where a fetch is the point.
struct ModelHelperTests {
    private let instanceID = UUID()

    private func shift(_ id: Int, start: Date, end: Date) -> CachedShift {
        CachedShift(
            serverID: id, instanceID: instanceID, title: "Shift \(id)", startsAt: start, endsAt: end,
            locationID: 1, shiftTypeID: 1, url: "https://example.com/shifts/\(id)"
        )
    }

    // MARK: CachedShift

    @Test func shiftDurationAndTimeStatus() {
        let now = Date()
        let past = shift(1, start: now.addingTimeInterval(-7200), end: now.addingTimeInterval(-3600))
        let ongoing = shift(2, start: now.addingTimeInterval(-1800), end: now.addingTimeInterval(1800))
        let future = shift(3, start: now.addingTimeInterval(3600), end: now.addingTimeInterval(10800))

        #expect(future.duration == 7200)
        #expect(future.durationInHours == 2)
        #expect(past.isPast && !past.isOngoing && !past.isFuture)
        #expect(ongoing.isOngoing && !ongoing.isPast && !ongoing.isFuture)
        #expect(future.isFuture && !future.isOngoing && !future.isPast)
    }

    @Test func nextShiftIsTheEarliestUpcomingOne() {
        let now = Date()
        let past = shift(1, start: now.addingTimeInterval(-7200), end: now.addingTimeInterval(-3600))
        let later = shift(2, start: now.addingTimeInterval(7200), end: now.addingTimeInterval(9000))
        let sooner = shift(3, start: now.addingTimeInterval(3600), end: now.addingTimeInterval(5400))

        #expect(CachedShift.nextShift(from: [past, later, sooner])?.serverID == 3)
        #expect(CachedShift.nextShift(from: [past]) == nil)
        #expect(CachedShift.upcomingShifts(from: [past, later, sooner]).map(\.serverID) == [3, 2])
    }

    @Test func shiftsAreGroupedByDayAndSortedWithinEachDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day1 = Date(timeIntervalSince1970: 1_800_000_000)
        let day2 = day1.addingTimeInterval(86_400)
        let a = shift(1, start: day2.addingTimeInterval(3600), end: day2.addingTimeInterval(7200))
        let b = shift(2, start: day1.addingTimeInterval(7200), end: day1.addingTimeInterval(9000))
        let c = shift(3, start: day1.addingTimeInterval(3600), end: day1.addingTimeInterval(5400))

        let groups = CachedShift.groupedByDay([a, b, c], calendar: calendar)
        #expect(groups.count == 2)
        #expect(groups[0].shifts.map(\.serverID) == [3, 2])
        #expect(groups[1].shifts.map(\.serverID) == [1])
        #expect(groups[0].day < groups[1].day)
    }

    // MARK: CachedNews

    private func news(_ id: Int, instance: UUID? = nil, pinned: Bool = false, created: TimeInterval = 0) -> CachedNews {
        CachedNews(
            serverID: id, instanceID: instance ?? instanceID, title: "News \(id)", text: "text",
            isMeeting: false, isPinned: pinned, isHighlighted: false,
            createdAt: Date(timeIntervalSince1970: created), url: "https://example.com/news/\(id)"
        )
    }

    @Test func newsIsSortedPinnedFirstThenNewestFirst() {
        let old = news(1, created: 100)
        let new = news(2, created: 200)
        let pinnedOld = news(3, pinned: true, created: 50)
        let pinnedNew = news(4, pinned: true, created: 300)
        #expect(CachedNews.sortedByRecency([old, new, pinnedOld, pinnedNew]).map(\.serverID) == [4, 3, 2, 1])
    }

    @Test func newsFromTwoInstancesOnTheSameServerIsMergedWithBothInstanceNames() {
        let a = Instance(name: "Account A", baseURL: "https://events.example.com/", apiKeyKeychainRef: "a")
        let b = Instance(name: "Account B", baseURL: "https://events.example.com", apiKeyKeychainRef: "b")
        let other = Instance(name: "Other", baseURL: "https://other.example.com", apiKeyKeychainRef: "c")
        let items = [
            news(1, instance: a.id), news(1, instance: b.id), news(1, instance: other.id), news(2, instance: a.id),
        ]

        let merged = CachedNews.mergedAcrossServers(items, instances: [a, b, other])
        #expect(merged.count == 3)
        #expect(merged[0].instanceNames == ["Account A", "Account B"])
        #expect(merged[1].instanceNames == ["Other"])
        #expect(merged[0].id == merged[0].item.uid)
    }

    @Test func newsFromAnUnknownInstanceIsKeptWithoutABadge() {
        let orphan = news(9, instance: UUID())
        let merged = CachedNews.mergedAcrossServers([orphan], instances: [])
        #expect(merged.count == 1)
        #expect(merged[0].instanceNames.isEmpty)
    }

    // MARK: Other models

    @Test func userDisplayNameUsesFirstAndLastNameWhenBothExist() {
        let full = CachedUser(serverID: 1, instanceID: instanceID, name: "nick", firstName: "Ada", lastName: "Lovelace", url: "u")
        let partial = CachedUser(serverID: 2, instanceID: instanceID, name: "nick", firstName: "Ada", url: "u")
        #expect(full.displayName == "Ada Lovelace")
        #expect(partial.displayName == "nick")
    }

    @Test func worklogsAreSortedNewestFirstAndSummed() {
        func log(_ id: Int, hours: Double, at: TimeInterval) -> CachedWorklog {
            CachedWorklog(
                serverID: id, instanceID: instanceID, workLogDescription: "w", hours: hours,
                createdByID: 1, workedAt: Date(timeIntervalSince1970: at)
            )
        }
        let logs = [log(1, hours: 1.5, at: 100), log(2, hours: 2, at: 300), log(3, hours: 0.5, at: 200)]
        #expect(CachedWorklog.sortedByDate(logs).map(\.serverID) == [2, 3, 1])
        #expect(CachedWorklog.totalHours(logs) == 4)
    }

    @Test func locationsAreSortedByNameNaturally() {
        func loc(_ id: Int, _ name: String) -> CachedLocation {
            CachedLocation(serverID: id, instanceID: instanceID, name: name, locationDescription: "", url: "u")
        }
        #expect(CachedLocation.sortedByName([loc(1, "Room 10"), loc(2, "Room 2"), loc(3, "Hall")]).map(\.name)
                == ["Hall", "Room 2", "Room 10"])
    }

    @Test func angelTypeMembershipsAreSortedByNameWithMissingNamesFirst() {
        func membership(_ id: Int, _ name: String?) -> CachedAngelTypeMembership {
            CachedAngelTypeMembership(serverID: id, instanceID: instanceID, angelTypeName: name, confirmed: true, supporter: false)
        }
        let sorted = CachedAngelTypeMembership.sortedByName([membership(1, "Zed"), membership(2, nil), membership(3, "Alpha")])
        #expect(sorted.map(\.serverID) == [2, 3, 1])
    }

    // MARK: NotificationLeadTimeSettings

    @Test func currentPlatformIsIOSOnThisTestPlatform() {
        #expect(NotificationLeadTimeSettings.currentPlatform == "ios")
    }

    @Test func touchAdvancesUpdatedAt() {
        let settings = NotificationLeadTimeSettings(platform: "ios", leadTimesMinutesRaw: "15")
        settings.updatedAt = Date(timeIntervalSince1970: 0)
        settings.touch()
        #expect(settings.updatedAt > Date(timeIntervalSince1970: 0))
    }

    @MainActor
    @Test func resolveForTheCurrentPlatformCreatesThenReusesTheRow() throws {
        let schema = Schema([NotificationLeadTimeSettings.self])
        let container = try ModelContainer(
            for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let first = NotificationLeadTimeSettings.resolve(in: context)
        let second = NotificationLeadTimeSettings.resolve(in: context)
        #expect(first.id == second.id)
        #expect(first.platform == "ios")
    }
}
