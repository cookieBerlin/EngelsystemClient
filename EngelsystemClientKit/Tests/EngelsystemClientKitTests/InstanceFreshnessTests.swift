import Foundation
import Testing
@testable import EngelsystemClientKit

@MainActor
struct InstanceFreshnessTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func freshness(_ ago: TimeInterval?, name: String = "Home", showsName: Bool = false) -> InstanceFreshness {
        InstanceFreshness(
            instanceID: UUID(), instanceName: name, lastSync: ago.map { now.addingTimeInterval(-$0) },
            showsName: showsName, now: now)
    }

    @Test func twelveHoursDecideBetweenCurrentAndStale() {
        #expect(freshness(3600).level == .current)
        #expect(freshness(12 * 3600 - 1).level == .current)
        #expect(freshness(12 * 3600).level == .stale)
        #expect(freshness(21 * 86400).level == .stale)
        #expect(freshness(nil).level == .neverSynced)
    }

    @Test func everyStateHasItsOwnSymbolAndOnlyWarningsAskForARefresh() {
        #expect(freshness(60).systemImage == "checkmark.circle")
        #expect(!freshness(60).needsRefresh)
        for warning in [freshness(13 * 3600), freshness(nil)] {
            #expect(warning.systemImage == "exclamationmark.triangle.fill")
            #expect(warning.needsRefresh)
            #expect(warning.text.hasSuffix(" – tap to refresh"))
        }
    }

    @Test func textNamesTheInstanceOnlyWhenSeveralAreListed() {
        #expect(freshness(2 * 3600).text.hasPrefix("Updated "))
        #expect(freshness(2 * 3600, showsName: true).text.hasPrefix("Home: updated "))
        #expect(freshness(nil).text == "Not synced yet – tap to refresh")
        #expect(freshness(nil, showsName: true).text == "Home: not synced yet – tap to refresh")
        #expect(freshness(10).text == "Updated just now")
    }

    @Test func accessibilityTextStatesTheStateInWords() {
        #expect(freshness(60).accessibilityText.hasPrefix("Up to date. "))
        #expect(freshness(13 * 3600).accessibilityText.hasPrefix("Warning, data is outdated. "))
        #expect(freshness(nil).accessibilityText.hasPrefix("Warning, no data yet. "))
    }

    @Test func rowsListOnlyActiveInstancesAndShowNamesFromTwoOn() {
        let a = Instance(name: "A", baseURL: "https://a.test", apiKeyKeychainRef: "a")
        let b = Instance(name: "B", baseURL: "https://b.test", apiKeyKeychainRef: "b", isActive: false)
        let c = Instance(name: "C", baseURL: "https://c.test", apiKeyKeychainRef: "c")
        let single = InstanceFreshness.rows(for: [a, b], lastSync: { _ in nil }, now: now)
        #expect(single.map(\.instanceName) == ["A"])
        #expect(single.allSatisfy { !$0.showsName })
        let several = InstanceFreshness.rows(
            for: [a, b, c], lastSync: { $0.name == "A" ? self.now : nil }, now: now)
        #expect(several.map(\.instanceName) == ["A", "C"])
        #expect(several.allSatisfy { $0.showsName })
        #expect(several.map(\.level) == [.current, .neverSynced])
        #expect(several[0].id == a.id)
    }
}

@MainActor
struct InstanceSyncQueueTests {
    @Test func syncsRunOneAfterTheOtherAndNeverTwiceForTheSameInstance() async {
        let queue = InstanceSyncQueue()
        let a = Instance(name: "A", baseURL: "https://a.test", apiKeyKeychainRef: "a")
        let b = Instance(name: "B", baseURL: "https://b.test", apiKeyKeychainRef: "b")
        var events: [String] = []
        let perform: (Instance) async -> Void = { instance in
            events.append("start \(instance.name)")
            await Task.yield()
            events.append("end \(instance.name)")
        }
        queue.enqueue(a, perform: perform)
        queue.enqueue(a, perform: perform) // already waiting
        queue.enqueue(b, perform: perform)
        await queue.waitUntilIdle()
        #expect(events == ["start A", "end A", "start B", "end B"])

        queue.enqueue(a, perform: perform) // the queue is usable again afterwards
        await queue.waitUntilIdle()
        #expect(events.suffix(2) == ["start A", "end A"])
    }
}
