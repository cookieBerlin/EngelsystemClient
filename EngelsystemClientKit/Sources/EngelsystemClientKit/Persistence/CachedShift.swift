import Foundation
import SwiftData

@Model
public final class CachedShift {
    // Composite unique key prevents collision across instances with the same server-assigned ID
    @Attribute(.unique) public var uid: String
    public var serverID: Int
    public var instanceID: UUID

    public var title: String
    public var shiftDescription: String
    public var startsAt: Date
    public var endsAt: Date

    // Flattened from API's location Reference
    public var locationID: Int
    public var locationName: String?

    // Flattened from API's shift_type Reference
    public var shiftTypeID: Int
    public var shiftTypeName: String?

    // Angel type the current user is signed up for, extracted from needed_angel_types
    public var angelTypeID: Int?
    public var angelTypeName: String?

    public var url: String
    public var scheduleGuid: String?
    public var cachedAt: Date

    // No relationship to Instance — it lives in a separate, CloudKit-backed
    // ModelConfiguration; see Instance.swift. Callers filter by `instanceID` instead.

    public init(
        serverID: Int,
        instanceID: UUID,
        title: String,
        shiftDescription: String = "",
        startsAt: Date,
        endsAt: Date,
        locationID: Int,
        locationName: String? = nil,
        shiftTypeID: Int,
        shiftTypeName: String? = nil,
        angelTypeID: Int? = nil,
        angelTypeName: String? = nil,
        url: String,
        scheduleGuid: String? = nil
    ) {
        self.uid = "\(instanceID.uuidString):\(serverID)"
        self.serverID = serverID
        self.instanceID = instanceID
        self.title = title
        self.shiftDescription = shiftDescription
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.locationID = locationID
        self.locationName = locationName
        self.shiftTypeID = shiftTypeID
        self.shiftTypeName = shiftTypeName
        self.angelTypeID = angelTypeID
        self.angelTypeName = angelTypeName
        self.url = url
        self.scheduleGuid = scheduleGuid
        self.cachedAt = Date()
    }
}

// MARK: - Mapping from the generated `Shift` DTO

public extension CachedShift {
    convenience init(shift: Shift, instanceID: UUID) {
        self.init(
            serverID: shift.id,
            instanceID: instanceID,
            title: shift.name,
            shiftDescription: shift.description,
            startsAt: shift.startsAt,
            endsAt: shift.endsAt,
            locationID: shift.location.id,
            locationName: shift.location.name,
            shiftTypeID: shift.shiftType.id,
            shiftTypeName: shift.shiftType.name,
            url: shift.url,
            scheduleGuid: shift.scheduleGuid?.uuidString
        )
    }

    /// Updates all fields from a freshly fetched `Shift` DTO (used by `ShiftSyncService`
    /// when a cached row already exists for this shift).
    func apply(_ shift: Shift) {
        title = shift.name
        shiftDescription = shift.description
        startsAt = shift.startsAt
        endsAt = shift.endsAt
        locationID = shift.location.id
        locationName = shift.location.name
        shiftTypeID = shift.shiftType.id
        shiftTypeName = shift.shiftType.name
        url = shift.url
        scheduleGuid = shift.scheduleGuid?.uuidString
        updateCacheTimestamp()
    }

    static func uid(instanceID: UUID, serverID: Int) -> String {
        "\(instanceID.uuidString):\(serverID)"
    }
}

// MARK: - Time status

public extension CachedShift {
    var duration: TimeInterval { endsAt.timeIntervalSince(startsAt) }
    var durationInHours: Double { duration / 3600.0 }

    var isFuture: Bool { startsAt > Date() }
    var isOngoing: Bool { let now = Date(); return startsAt <= now && now <= endsAt }
    var isPast: Bool { endsAt < Date() }

    func notificationDate(minutesBefore: Int = 15) -> Date? {
        let date = startsAt.addingTimeInterval(-TimeInterval(minutesBefore * 60))
        return date > Date() ? date : nil
    }

    func formattedTimeRange() -> String {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return "\(f.string(from: startsAt)) – \(f.string(from: endsAt))"
    }

    func updateCacheTimestamp() { cachedAt = Date() }
}

// MARK: - Sorting & filtering

public extension CachedShift {
    static func sortedByStartTime(_ shifts: [CachedShift]) -> [CachedShift] {
        shifts.sorted { $0.startsAt < $1.startsAt }
    }

    static func upcomingShifts(from shifts: [CachedShift]) -> [CachedShift] {
        shifts.filter { $0.isFuture }.sorted { $0.startsAt < $1.startsAt }
    }

    /// Next upcoming shift — primarily for the Watch app
    static func nextShift(from shifts: [CachedShift]) -> CachedShift? {
        upcomingShifts(from: shifts).first
    }

    /// Groups shifts by calendar day (each `day` is that day's `startOfDay`), sorted by
    /// day ascending, each day's shifts sorted by start time — backs the iOS Shifts
    /// screen's date-grouped list (a shift row on its own only shows a time, not a
    /// date; the day header carries that instead).
    static func groupedByDay(_ shifts: [CachedShift], calendar: Calendar = .current) -> [(day: Date, shifts: [CachedShift])] {
        let grouped = Dictionary(grouping: shifts) { calendar.startOfDay(for: $0.startsAt) }
        return grouped.keys.sorted().map { day in (day, sortedByStartTime(grouped[day] ?? [])) }
    }
}
