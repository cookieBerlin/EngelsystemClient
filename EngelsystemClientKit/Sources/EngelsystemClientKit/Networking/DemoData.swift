import Foundation

/// Static mock data returned by `APIClient` for a demo instance (see `Instance.demoBaseURL`),
/// so the app can be tried end-to-end without a real Engelsystem server or API key.
/// Lives entirely in the networking layer — views/view models never know they're
/// looking at demo data instead of a real response.
enum DemoData {
    static let locations: [Location] = [
        Location(
            id: 1, name: "Heaven", description: "Main hall and central meeting point",
            mapUrl: nil, contact: ContactDect(dect: "1000"),
            url: "https://demo.engelsystem.local/locations/1"
        ),
        Location(
            id: 2, name: "Chill Space", description: "Quiet area to rest between shifts",
            mapUrl: nil, contact: ContactDect(dect: nil),
            url: "https://demo.engelsystem.local/locations/2"
        ),
    ]

    static let shiftTypes: [ShiftType] = [
        ShiftType(id: 1, name: "Set-up", description: "Building up the venue before the event"),
        ShiftType(id: 2, name: "Info Desk", description: "Helping visitors at the info desk"),
        ShiftType(id: 3, name: "Teardown", description: "Tearing down the venue after the event"),
    ]

    static let angelTypes: [AngelType] = [
        AngelType(
            id: 1, name: "Engel", description: "General-purpose helper, no prior experience needed",
            restricted: false,
            contact: AngelTypeContact(name: "Coordination", email: "coordination@demo.engelsystem.local", dect: nil),
            url: "https://demo.engelsystem.local/angeltypes/1"
        ),
    ]

    static var info: EventInfo {
        let now = Date()
        return EventInfo(
            api: "1.0.0-demo",
            spec: "https://demo.engelsystem.local/openapi",
            name: "Demo Congress",
            appName: "Engelsystem",
            url: "https://demo.engelsystem.local",
            timezone: "Europe/Berlin",
            buildup: EventInfoBuildup(start: now.addingTimeInterval(-2 * 86400)),
            event: EventInfoEvent(start: now.addingTimeInterval(-1 * 86400), end: now.addingTimeInterval(2 * 86400)),
            teardown: EventInfoTeardown(end: now.addingTimeInterval(3 * 86400))
        )
    }

    static var news: [News] {
        let now = Date()
        return [
            News(
                id: 1, name: "Welcome to the Demo Congress!",
                text: "Thanks for trying out the app in demo mode. Everything you see here is sample data — no real server involved.",
                isMeeting: false, isPinned: true, isHighlighted: true,
                createdAt: now.addingTimeInterval(-3600), updatedAt: nil,
                url: "https://demo.engelsystem.local/news/1"
            ),
            News(
                id: 2, name: "Heaven build-up meeting",
                text: "First helper meeting takes place at Heaven. Please bring your own seating.",
                isMeeting: true, isPinned: false, isHighlighted: false,
                createdAt: now.addingTimeInterval(-7200), updatedAt: nil,
                url: "https://demo.engelsystem.local/news/2"
            ),
        ]
    }

    static var shifts: [Shift] {
        let now = Date()
        return [
            Shift(
                id: 1, name: "Info Desk Shift", description: "Help visitors find their way",
                startsAt: now.addingTimeInterval(3600), endsAt: now.addingTimeInterval(3600 * 4),
                location: Reference(id: 1, name: "Heaven"),
                shiftType: Reference(id: 2, name: "Info Desk"),
                scheduleGuid: nil, createdAt: nil, updatedAt: nil,
                neededAngelTypes: [], url: "https://demo.engelsystem.local/shifts/1"
            ),
            Shift(
                id: 2, name: "Set-up Shift", description: "Help build up the chill space",
                startsAt: now.addingTimeInterval(-3600 * 20), endsAt: now.addingTimeInterval(-3600 * 16),
                location: Reference(id: 2, name: "Chill Space"),
                shiftType: Reference(id: 1, name: "Set-up"),
                scheduleGuid: nil, createdAt: nil, updatedAt: nil,
                neededAngelTypes: [], url: "https://demo.engelsystem.local/shifts/2"
            ),
        ]
    }

    static var worklogs: [Worklog] {
        let now = Date()
        return [
            Worklog(
                id: 1, description: "Helped build up the chill space", hours: 3.5,
                createdBy: Reference(id: 1, name: "Demo Angel"),
                workedAt: now.addingTimeInterval(-3600 * 16), createdAt: nil, updatedAt: nil
            ),
        ]
    }

    static let ownAngelTypes: [UserAngelType] = [
        UserAngelType(confirmed: true, supporter: false, angeltype: Reference(id: 1, name: "Engel")),
    ]

    static var ownProfile: UsersIdGet200ResponseData {
        UsersIdGet200ResponseData(
            id: 1, name: "demo", firstName: "Demo", lastName: "Angel", pronoun: "they/them",
            contact: UserContact(dect: "1000", mobile: nil),
            url: "https://demo.engelsystem.local/users/1",
            email: "demo@demo.engelsystem.local", tshirtSize: "L",
            dates: UserDetailAllOfDates(plannedArrival: nil, plannedDeparture: nil, arrival: nil),
            language: "en_US", arrived: true, oauth: []
        )
    }

    /// Small artificial delay so demo mode still exercises loading states in the UI.
    static func simulateLatency() async {
        try? await Task.sleep(nanoseconds: 300_000_000)
    }
}
