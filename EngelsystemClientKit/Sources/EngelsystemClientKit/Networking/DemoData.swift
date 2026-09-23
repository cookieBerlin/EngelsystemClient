import Foundation

/// Static mock data returned by `APIClient` for a demo instance (see `Instance.demoBaseURL`),
/// so the app can be tried end-to-end without a real Engelsystem server or API key.
/// Lives entirely in the networking layer — views/view models never know they're
/// looking at demo data instead of a real response.
enum DemoData {
    /// Backs the "start a new conversation" picker (`APIClient.fetchUsers`). `id: 2`/`3`
    /// reuse the same demo users already referenced elsewhere (News comments,
    /// worklogs) for consistency; `id: 4` has no existing demo conversation, so
    /// picking them exercises the "start a brand new conversation" path specifically.
    static let users: [Reference] = [
        Reference(id: 2, name: "Helper Angel"),
        Reference(id: 3, name: "Another Angel"),
        Reference(id: 4, name: "Night Shift Nick"),
    ]

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

    /// Backs `APIClient.fetchLocation(id:_:)`'s demo path — `nil` for an unknown id,
    /// matching the real `GET /locations/{id}` endpoint's 404 behavior.
    static func location(id: Int) -> Location? {
        locations.first { $0.id == id }
    }

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
                // Deliberately has both a `[more]` split *and* comments — the only
                // demo item that does, so the "Read More"/"Show Less" button and the
                // "N Comments" link both render on the same row at once. That
                // combination is exactly what's needed to exercise (and regression-
                // test) the 2026-09-22 bug where tapping one could also silently
                // activate the other.
                text: "Thanks for trying out the app in demo mode. [more] Everything you see here is sample data — no real server involved.",
                isMeeting: false, isPinned: true, isHighlighted: true,
                createdAt: now.addingTimeInterval(-3600), updatedAt: nil,
                url: "https://demo.engelsystem.local/news/1",
                commentsCount: 2
            ),
            News(
                id: 2, name: "Heaven build-up meeting",
                text: "First helper meeting takes place at Heaven. Please bring your own seating.",
                isMeeting: true, isPinned: false, isHighlighted: false,
                createdAt: now.addingTimeInterval(-7200), updatedAt: nil,
                url: "https://demo.engelsystem.local/news/2",
                commentsCount: 0
            ),
        ]
    }

    /// Backs `APIClient.fetchNewsDetail` for a demo instance — `nil` for an unknown
    /// `id`, matching the real endpoint's 404 (`APIClient` maps that to `.notFound`).
    /// Only item 1 has sample comments, so demo mode also exercises the "no comments
    /// yet" empty state via item 2.
    static func newsDetail(id: Int) -> NewsDetail? {
        guard let item = news.first(where: { $0.id == id }) else { return nil }
        let now = Date()
        let comments: [NewsComment]
        switch id {
        case 1:
            comments = [
                NewsComment(
                    id: 1, text: "Looking forward to it!",
                    user: Reference(id: 2, name: "Helper Angel"),
                    createdAt: now.addingTimeInterval(-3000), updatedAt: nil
                ),
                NewsComment(
                    id: 2, text: "Thanks for the update, see you there.",
                    user: Reference(id: 3, name: "Another Angel"),
                    createdAt: now.addingTimeInterval(-1800), updatedAt: nil
                ),
            ]
        default:
            comments = []
        }
        return NewsDetail(
            id: item.id, name: item.name, text: item.text, isMeeting: item.isMeeting,
            isPinned: item.isPinned, isHighlighted: item.isHighlighted,
            createdAt: item.createdAt, updatedAt: item.updatedAt, url: item.url,
            commentsCount: item.commentsCount, comments: comments
        )
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

    // MARK: - Messages (2026-09-23)
    //
    // Unlike every other DemoData property/method above (all read-only), Messages is
    // this app's first write feature — demo mode needs to actually simulate sending/
    // deleting/marking read, not just return a fixed snapshot, or "try demo mode"
    // would misrepresent the real feature. Delegates to `DemoMessageStore`, the one
    // piece of *mutable* state in this otherwise fully static/immutable file.

    static func conversations() async -> [Conversation] {
        await DemoMessageStore.shared.conversations
    }

    static func conversation(otherUserID: Int) async -> [Message] {
        await DemoMessageStore.shared.messages(withOtherUserID: otherUserID)
    }

    static func sendMessage(to otherUserID: Int, text: String) async -> Message {
        await DemoMessageStore.shared.send(to: otherUserID, text: text)
    }

    static func deleteMessage(id: Int) async {
        await DemoMessageStore.shared.delete(messageID: id)
    }

    static func setMessageRead(id: Int, read: Bool) async -> Message? {
        await DemoMessageStore.shared.setRead(messageID: id, read: read)
    }
}

/// The one piece of mutable state in `DemoData` — everything else there is a fixed,
/// immutable snapshot, since every other endpoint is read-only. `@MainActor`-isolated
/// for safe mutable global state without a bespoke lock, same reasoning as `DebugLog`;
/// callers `await` into it same as any other actor-isolated access, regardless of
/// whether `APIClient` itself happens to be running on the main actor.
///
/// Demo user id `1` ("demo"/"Demo Angel", see `DemoData.ownProfile`) is always the
/// sender/receiver representing "the signed-in user" here.
@MainActor
private final class DemoMessageStore {
    static let shared = DemoMessageStore()

    private static let demoUserID = 1
    private var messagesByOtherUserID: [Int: [Message]]
    private var nextMessageID = 100

    private init() {
        let now = Date()
        // One seeded conversation (with "Helper Angel", id 2) so the conversation
        // list isn't empty in demo mode — one incoming, unread message, so the
        // "mark as read on open"/unread-badge behavior has something to show.
        messagesByOtherUserID = [
            2: [
                Message(
                    id: 1, text: "Could you cover my shift tomorrow?",
                    sender: Reference(id: 2, name: "Helper Angel"),
                    receiver: Reference(id: Self.demoUserID, name: "demo"),
                    read: false, createdAt: now.addingTimeInterval(-3600), updatedAt: nil
                ),
            ],
        ]
    }

    var conversations: [Conversation] {
        messagesByOtherUserID.compactMap { otherUserID, messages -> Conversation? in
            guard let latest = messages.max(by: { $0.createdAt < $1.createdAt }) else { return nil }
            let otherUser = latest.sender.id == otherUserID ? latest.sender : latest.receiver
            let unread = messages.filter { !$0.read && $0.receiver.id == Self.demoUserID }.count
            return Conversation(otherUser: otherUser, latestMessage: latest, unreadMessages: unread)
        }.sorted { $0.latestMessage.createdAt > $1.latestMessage.createdAt }
    }

    func messages(withOtherUserID otherUserID: Int) -> [Message] {
        (messagesByOtherUserID[otherUserID] ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    func send(to otherUserID: Int, text: String) -> Message {
        nextMessageID += 1
        let otherUserName = DemoData.users.first { $0.id == otherUserID }?.name ?? "User \(otherUserID)"
        let message = Message(
            id: nextMessageID, text: text,
            sender: Reference(id: Self.demoUserID, name: "demo"),
            receiver: Reference(id: otherUserID, name: otherUserName),
            read: true, createdAt: Date(), updatedAt: nil
        )
        messagesByOtherUserID[otherUserID, default: []].append(message)
        return message
    }

    func delete(messageID: Int) {
        for otherUserID in messagesByOtherUserID.keys {
            messagesByOtherUserID[otherUserID]?.removeAll { $0.id == messageID }
        }
    }

    func setRead(messageID: Int, read: Bool) -> Message? {
        for otherUserID in messagesByOtherUserID.keys {
            guard let index = messagesByOtherUserID[otherUserID]?.firstIndex(where: { $0.id == messageID }) else { continue }
            let existing = messagesByOtherUserID[otherUserID]![index]
            let updated = Message(
                id: existing.id, text: existing.text, sender: existing.sender,
                receiver: existing.receiver, read: read, createdAt: existing.createdAt,
                updatedAt: Date()
            )
            messagesByOtherUserID[otherUserID]![index] = updated
            return updated
        }
        return nil
    }
}
