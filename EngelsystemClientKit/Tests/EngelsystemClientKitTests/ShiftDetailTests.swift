import Foundation
import Testing
@testable import EngelsystemClientKit

@MainActor
struct ShiftDetailTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let now = Date(timeIntervalSince1970: 1_800_000_000 - 10 * 3600)
    private let own = Reference(id: 1, name: "demo")

    private func entry(
        _ id: Int, _ user: Reference, freeloaded: Bool? = nil, canSignOut: Bool? = nil,
        freeloadedBy: Reference? = nil, comment: String? = nil
    ) -> ShiftEntry {
        ShiftEntry(
            id: id, user: user, freeloadedBy: freeloadedBy, freeloaded: freeloaded, canSignOut: canSignOut,
            userComment: nil, freeloadedComment: comment)
    }

    private func shift(
        team: [NeededAngelType] = [], signOutUntil: Date? = nil, end: TimeInterval = 5400,
        talk: String? = nil, url: String = "https://example.org/shifts/7", description: String = "Bring gloves",
        tags: [String] = [], night: Bool? = nil, signupFrom: Date? = nil, typeDescription: String? = "About the type"
    ) -> CachedShift {
        CachedShift(
            serverID: 7, instanceID: UUID(), title: "Desk", shiftDescription: description,
            startsAt: start, endsAt: start.addingTimeInterval(end), locationID: 1, locationName: "Heaven",
            shiftTypeID: 2, shiftTypeName: "Info Desk", url: url,
            shiftTypeDescription: typeDescription, signOutUntil: signOutUntil, signupAvailableFrom: signupFrom,
            tags: tags, talkURL: talk, nightShift: night, teamData: CachedShift.encodeTeam(team))
    }

    private func type(_ name: String?, needs: Int, _ entries: [ShiftEntry]) -> NeededAngelType {
        NeededAngelType(entries: entries, angelType: Reference(id: 5, name: name), needs: needs)
    }

    @Test func headerFieldsAreTrimmedAndOptional() {
        let detail = ShiftDetail(
            shift: shift(description: "  ", tags: ["quiet"], night: true, typeDescription: nil), ownUserID: 1, now: now)
        #expect(detail.title == "Desk")
        #expect(detail.shiftTypeName == "Info Desk")
        #expect(detail.shiftTypeDescription == nil)
        #expect(detail.description == nil)
        #expect(detail.locationName == "Heaven")
        #expect(detail.tags == ["quiet"])
        #expect(detail.isNightShift)
        #expect(!detail.isOwnShift)
        #expect(detail.signOut == nil)
        #expect(ShiftDetail(shift: shift(), ownUserID: 1, now: now).description == "Bring gloves")
    }

    @Test func durationIsWrittenInHoursAndMinutes() {
        #expect(ShiftDetail(shift: shift(end: 3 * 3600), ownUserID: nil).durationText == "3 h")
        #expect(ShiftDetail(shift: shift(end: 5400), ownUserID: nil).durationText == "1 h 30 min")
        #expect(ShiftDetail(shift: shift(end: 1800), ownUserID: nil).durationText == "30 min")
    }

    @Test func onlyWebLinksAndFutureSignupAreShown() {
        let detail = ShiftDetail(
            shift: shift(talk: "https://talk.test/1", signupFrom: now.addingTimeInterval(60)), ownUserID: nil, now: now)
        #expect(detail.talkURL?.absoluteString == "https://talk.test/1")
        #expect(detail.signupAvailableFrom != nil)

        let other = ShiftDetail(
            shift: shift(talk: "javascript:alert(1)", signupFrom: now.addingTimeInterval(-60)), ownUserID: nil, now: now)
        #expect(other.talkURL == nil)
        #expect(other.signupAvailableFrom == nil)
        #expect(ShiftDetail(shift: shift(talk: "  "), ownUserID: nil, now: now).talkURL == nil)
    }

    @Test func occupancyTextCoversFullOverbookedAndAdditionalOnly() {
        let one = entry(1, own), two = entry(2, Reference(id: 2, name: "Helper"))
        let detail = ShiftDetail(shift: shift(team: [
            type("Info Desk Angel", needs: 3, [one]),
            type("Engel", needs: 1, [one, two]),
            type(nil, needs: 0, [one]),
        ]), ownUserID: 1, now: now)
        #expect(detail.team.map(\.occupancyText) == ["1 of 3", "2 (needs 1)", "1"])
        #expect(detail.team[2].angelTypeName == "Unknown")
    }

    @Test func membersCarryOwnAndFreeloadedFlags() {
        let other = Reference(id: 2, name: "Helper")
        let nameless = Reference(id: 3, name: nil)
        let moderator = Reference(id: 9, name: "Lead")
        let detail = ShiftDetail(shift: shift(team: [type("Engel", needs: 4, [
            entry(1, own, freeloaded: false),
            entry(2, other, freeloaded: true, freeloadedBy: moderator, comment: " no show "),
            entry(3, nameless, freeloadedBy: moderator), // COMPAT(#1723): detected by freeloaded_by
            entry(4, Reference(id: 4, name: "Plain")),
        ])]), ownUserID: 1, now: now)
        let members = detail.team[0].members
        #expect(members[0].isOwn && !members[0].didNotShow)
        #expect(members[1].didNotShow && members[1].markedBy == "Lead" && members[1].comment == "no show")
        #expect(members[2].didNotShow && members[2].name == "Unknown")
        #expect(!members[3].didNotShow && !members[3].isOwn && members[3].markedBy == nil)
        #expect(detail.isOwnShift)
    }

    @Test func signOutUsesTheServerDeadlineAndCanSignOut() {
        let deadline = start.addingTimeInterval(-3600)
        let open = ShiftDetail(shift: shift(
            team: [type("Engel", needs: 1, [entry(1, own, canSignOut: true)])], signOutUntil: deadline),
            ownUserID: 1, now: now)
        #expect(open.signOut == ShiftDetail.SignOut(
            deadline: deadline, isAssumed: false, isOpen: true, browserURL: URL(string: "https://example.org/shifts/7")))

        // The server says no even though the deadline lies ahead.
        let denied = ShiftDetail(shift: shift(
            team: [type("Engel", needs: 1, [entry(1, own, canSignOut: false)])], signOutUntil: deadline),
            ownUserID: 1, now: now)
        #expect(denied.signOut?.isOpen == false)

        // The deadline has passed.
        let late = ShiftDetail(shift: shift(
            team: [type("Engel", needs: 1, [entry(1, own, canSignOut: true)])], signOutUntil: deadline),
            ownUserID: 1, now: deadline.addingTimeInterval(1))
        #expect(late.signOut?.isOpen == false)
    }

    @Test func withoutServerFieldsTheUsualThreeHoursApply() {
        let team = [type("Engel", needs: 1, [entry(1, own)])]
        let before = ShiftDetail(shift: shift(team: team), ownUserID: 1, now: now)
        #expect(before.signOut?.isAssumed == true)
        #expect(before.signOut?.deadline == start.addingTimeInterval(-3 * 3600))
        #expect(before.signOut?.isOpen == true)

        let after = ShiftDetail(shift: shift(team: team), ownUserID: 1, now: start.addingTimeInterval(-3 * 3600 + 1))
        #expect(after.signOut?.isOpen == false)

        // A shift that already ended offers nothing, and an unusable link means no button.
        let ended = ShiftDetail(shift: shift(team: team, signOutUntil: start.addingTimeInterval(9999)), ownUserID: 1,
                                now: start.addingTimeInterval(6000))
        #expect(ended.signOut?.isOpen == false)
        let noLink = ShiftDetail(shift: shift(team: team, url: "not a url"), ownUserID: 1, now: now)
        #expect(noLink.signOut?.browserURL == nil)
    }

    @Test func shiftFeaturesAreReadFromTheSyncedFields() {
        func dto(typeDescription: String?, signOut: Date?, entries: [ShiftEntry]) -> Shift {
            Shift(
                id: 1, name: "n", description: "", startsAt: start, endsAt: start, location: Reference(id: 1, name: "L"),
                shiftType: ShiftTypeReference(id: 1, name: "T", description: typeDescription), signOutUntil: signOut,
                scheduleGuid: nil, createdAt: nil, updatedAt: nil,
                neededAngelTypes: entries.isEmpty ? [] : [type("Engel", needs: 1, entries)], url: "u")
        }
        #expect(ServerCapabilities.shiftFeaturesSupported(by: []).isEmpty)

        let none = ServerCapabilities.shiftFeaturesSupported(by: [dto(typeDescription: nil, signOut: nil, entries: [])])
        #expect(none == [.shiftTypeDescription: false, .signOutDeadline: false])

        let all = ServerCapabilities.shiftFeaturesSupported(by: [
            dto(typeDescription: "d", signOut: start, entries: [entry(1, own, freeloaded: false, canSignOut: true)]),
        ])
        #expect(all == [.shiftTypeDescription: true, .signOutDeadline: true, .shiftTeam: true])

        let oldEntries = ServerCapabilities.shiftFeaturesSupported(by: [
            dto(typeDescription: nil, signOut: nil, entries: [entry(1, own)]),
        ])
        #expect(oldEntries == [.shiftTypeDescription: false, .signOutDeadline: false, .shiftTeam: false])

        // The deadline can also come from an entry flag alone (#1723 without #1722).
        let flagOnly = ServerCapabilities.shiftFeaturesSupported(by: [
            dto(typeDescription: nil, signOut: nil, entries: [entry(1, own, canSignOut: true)]),
        ])
        #expect(flagOnly[.signOutDeadline] == true)
    }
}
