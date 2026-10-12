import Foundation
import SwiftData
import Testing
@testable import EngelsystemClientKit

private final class RecordingKeyStore: APIKeyStore, @unchecked Sendable {
    var deleted: [String] = []
    struct Failure: Error {}
    var failDelete = false
    func save(apiKey: String, for reference: String) throws {}
    func loadAPIKey(for reference: String) throws -> String { throw Failure() }
    func deleteAPIKey(for reference: String) throws {
        if failDelete { throw Failure() }
        deleted.append(reference)
    }
}

@MainActor
private func makeContext() throws -> ModelContext {
    let schema = Schema([
        Instance.self, NotificationLeadTimeSettings.self, CachedShift.self, CachedNews.self, CachedUser.self,
        CachedWorklog.self, CachedAngelTypeMembership.self, CachedLocation.self,
    ])
    let container = try ModelContainer(
        for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
    )
    return ModelContext(container)
}

@MainActor
struct InstanceMaintenanceTests {
    @Test func setActiveFlipsTheFlagAndPersists() throws {
        let context = try makeContext()
        let instance = Instance(name: "I", baseURL: "https://x.test", apiKeyKeychainRef: "r")
        context.insert(instance)
        instance.setActive(false, in: context)
        #expect(!instance.isActive)
        instance.setActive(true, in: context)
        #expect(instance.isActive)
    }

    @Test func leadTimesAreSortedAndFallBackToTheDefaults() {
        let ios = NotificationLeadTimeSettings(platform: "ios", leadTimesMinutesRaw: "60,15,30")
        #expect(NotificationLeadTimeSettings.leadTimes(for: "ios", in: [ios]) == [15, 30, 60])
        #expect(NotificationLeadTimeSettings.leadTimes(for: "watch", in: [ios])
                == NotificationLeadTimeSettings.defaultLeadTimesMinutes)
    }

    @Test func addingAndRemovingLeadTimesPersistsPerPlatform() throws {
        let context = try makeContext()
        NotificationLeadTimeSettings.addLeadTime(60, for: "watch", in: context)
        NotificationLeadTimeSettings.addLeadTime(60, for: "watch", in: context) // duplicate ignored
        let rows = try context.fetch(FetchDescriptor<NotificationLeadTimeSettings>())
        #expect(NotificationLeadTimeSettings.leadTimes(for: "watch", in: rows) == [15, 60])

        NotificationLeadTimeSettings.removeLeadTime(15, for: "watch", in: context)
        let after = try context.fetch(FetchDescriptor<NotificationLeadTimeSettings>())
        #expect(NotificationLeadTimeSettings.leadTimes(for: "watch", in: after) == [60])
    }

    // Saved before returning: batch deletes (`delete(model:where:)`) act on the store, so
    // they only see rows that have been persisted.
    private func seed(in context: ModelContext) throws -> (Instance, Instance) {
        let mine = Instance(name: "Mine", baseURL: "https://a.test", apiKeyKeychainRef: "ref-a")
        let other = Instance(name: "Other", baseURL: "https://b.test", apiKeyKeychainRef: "ref-b")
        context.insert(mine)
        context.insert(other)
        for owner in [mine, other] {
            let id = owner.id
            let now = Date()
            context.insert(CachedShift(serverID: 1, instanceID: id, title: "S", startsAt: now, endsAt: now, locationID: 1, shiftTypeID: 1, url: "u"))
            context.insert(CachedNews(serverID: 1, instanceID: id, title: "N", text: "t", isMeeting: false, isPinned: false, isHighlighted: false, createdAt: now, url: "u"))
            context.insert(CachedUser(serverID: 1, instanceID: id, name: "U", url: "u"))
            context.insert(CachedWorklog(serverID: 1, instanceID: id, workLogDescription: "w", hours: 1, createdByID: 1, workedAt: now))
            context.insert(CachedAngelTypeMembership(serverID: 1, instanceID: id, confirmed: true, supporter: false))
            context.insert(CachedLocation(serverID: 1, instanceID: id, name: "L", locationDescription: "", url: "u"))
        }
        try context.save()
        return (mine, other)
    }

    @Test func deletingWithFullScopeRemovesTheInstanceItsKeysAndAllItsCaches() throws {
        let context = try makeContext()
        let (mine, other) = try seed(in: context)
        let first = RecordingKeyStore(), second = RecordingKeyStore()
        second.failDelete = true // a store that can't delete is skipped, not fatal

        InstanceRemoval.delete(mine, in: context, keyStores: [first, second], scope: .all)

        #expect(first.deleted == ["ref-a"])
        #expect(try context.fetch(FetchDescriptor<Instance>()).map(\.id) == [other.id])
        #expect(try context.fetch(FetchDescriptor<CachedShift>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<CachedNews>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<CachedUser>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<CachedWorklog>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<CachedAngelTypeMembership>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<CachedLocation>()).count == 1)
    }

    @Test func deletingWithShiftsOnlyScopeLeavesOtherCachesAlone() throws {
        let context = try makeContext()
        let (mine, _) = try seed(in: context)
        InstanceRemoval.delete(mine, in: context, keyStores: [], scope: .shiftsOnly)
        #expect(try context.fetch(FetchDescriptor<CachedShift>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<CachedNews>()).count == 2) // untouched
    }
}
