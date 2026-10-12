import Foundation
import Testing
import EngelsystemClientKit
@testable import EngelsystemClient

struct InstanceScopeTests {
    private let a = Instance(name: "A", baseURL: "https://a.test", apiKeyKeychainRef: "a")
    private let b = Instance(name: "B", baseURL: "https://b.test", apiKeyKeychainRef: "b")

    @Test func aSingleInstanceIsAlwaysMergedAndUnknownValuesFallBackToMerged() {
        #expect(InstanceScope.displayMode(raw: "sectioned", instanceCount: 1) == .merged)
        #expect(InstanceScope.displayMode(raw: "sectioned", instanceCount: 2) == .sectioned)
        #expect(InstanceScope.displayMode(raw: "switcher", instanceCount: 3) == .switcher)
        #expect(InstanceScope.displayMode(raw: "nonsense", instanceCount: 2) == .merged)
        #expect(MultiInstanceDisplayMode.stored(raw: "switcher") == .switcher)
        #expect(MultiInstanceDisplayMode.stored(raw: "") == .merged)
    }

    @Test func itemsAreFilteredToTheGivenInstances() {
        let mine = CachedUser(serverID: 1, instanceID: a.id, name: "mine", url: "u")
        let theirs = CachedUser(serverID: 2, instanceID: b.id, name: "theirs", url: "u")
        let stray = CachedUser(serverID: 3, instanceID: UUID(), name: "stray", url: "u")
        let result = InstanceScope.filter([mine, theirs, stray], to: [a], instanceID: \.instanceID)
        #expect(result.map(\.name) == ["mine"])
    }

    @Test func theSwitcherShowsTheSelectedInstanceElseTheFirst() {
        #expect(InstanceScope.switcherInstance(in: [a, b], selected: b.id)?.name == "B")
        #expect(InstanceScope.switcherInstance(in: [a, b], selected: UUID())?.name == "A")
        #expect(InstanceScope.switcherInstance(in: [a, b], selected: nil)?.name == "A")
        #expect(InstanceScope.switcherInstance(in: [], selected: nil) == nil)
    }

    @Test func instancesAndNamesAreLookedUpByID() {
        #expect(InstanceScope.instance(withID: a.id, in: [a, b])?.name == "A")
        #expect(InstanceScope.instance(withID: UUID(), in: [a, b]) == nil)
        #expect(InstanceScope.instanceName(withID: b.id, in: [a, b]) == "B")
        #expect(InstanceScope.instanceName(withID: UUID(), in: [a, b]) == nil)
    }

    @Test func aShiftsLocationMatchesOnInstanceAndServerID() {
        let shift = CachedShift(
            serverID: 1, instanceID: a.id, title: "S", startsAt: Date(), endsAt: Date(),
            locationID: 7, shiftTypeID: 1, url: "u"
        )
        let right = CachedLocation(serverID: 7, instanceID: a.id, name: "Right", locationDescription: "", url: "u")
        let otherInstance = CachedLocation(serverID: 7, instanceID: b.id, name: "Wrong", locationDescription: "", url: "u")
        let otherID = CachedLocation(serverID: 8, instanceID: a.id, name: "Wrong", locationDescription: "", url: "u")
        #expect(InstanceScope.location(for: shift, in: [otherInstance, otherID, right])?.name == "Right")
        #expect(InstanceScope.location(for: shift, in: [otherInstance, otherID]) == nil)
    }

    @Test func dayHeadersSayTodayTomorrowOrTheDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(InstanceScope.dayHeaderText(now, calendar: calendar, now: now) == "Today")
        #expect(InstanceScope.dayHeaderText(now.addingTimeInterval(86_400), calendar: calendar, now: now) == "Tomorrow")
        let later = now.addingTimeInterval(5 * 86_400)
        #expect(InstanceScope.dayHeaderText(later, calendar: calendar, now: now)
                == later.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        _ = InstanceScope.dayHeaderText(Date())
    }

    private func conversation(user: Int, at seconds: TimeInterval) -> Conversation {
        let sender = Reference(id: user, name: "U\(user)")
        let message = Message(
            id: user, text: "t", sender: sender, receiver: Reference(id: 0, name: "me"),
            read: true, createdAt: Date(timeIntervalSince1970: seconds), updatedAt: nil
        )
        return Conversation(otherUser: sender, latestMessage: message, unreadMessages: 0)
    }

    @Test func conversationsAreSortedNewestFirstPerInstanceAndMerged() {
        let old = conversation(user: 1, at: 100)
        let mid = conversation(user: 2, at: 200)
        let new = conversation(user: 3, at: 300)
        let byInstance = [a.id: [old, new], b.id: [mid]]

        #expect(InstanceScope.conversations(for: a, in: byInstance).map(\.otherUser.id) == [3, 1])
        #expect(InstanceScope.conversations(for: Instance(name: "C", baseURL: "https://c.test", apiKeyKeychainRef: "c"), in: byInstance).isEmpty)
        let merged = InstanceScope.allConversations(instances: [a, b], byInstanceID: byInstance)
        #expect(merged.map(\.conversation.otherUser.id) == [3, 2, 1])
        #expect(merged.map(\.instance.name) == ["A", "B", "A"])
    }

    @Test func theStartSyncNeedsTheToggleAndAnActiveInstance() {
        #expect(MainSyncStatus.shouldRunStartSync(syncOnAppStartEnabled: true, activeInstanceCount: 1))
        #expect(!MainSyncStatus.shouldRunStartSync(syncOnAppStartEnabled: false, activeInstanceCount: 1))
        #expect(!MainSyncStatus.shouldRunStartSync(syncOnAppStartEnabled: true, activeInstanceCount: 0))
    }
}
