import Foundation
import Testing
@testable import EngelsystemClientKit

@MainActor
struct InstancePaletteTests {
    private func instance(_ name: String, created: TimeInterval, color: String? = nil) -> Instance {
        let instance = Instance(name: name, baseURL: "https://\(name).test", apiKeyKeychainRef: name)
        instance.createdAt = Date(timeIntervalSince1970: created)
        instance.colorKey = color
        return instance
    }

    @Test func storedKeysResolveAndUnknownOnesMeanAuto() {
        #expect(InstancePalette.stored("teal") == .teal)
        #expect(InstancePalette.stored("nonsense") == nil)
        #expect(InstancePalette.stored(nil) == nil)
        #expect(InstancePalette.red.title == "Red")
        #expect(InstancePalette.indigo.id == "indigo")
        #expect(InstancePalette.allCases.count == 8)
    }

    @Test func autoColorsFollowTheCreationOrderAndNeverRepeat() {
        let a = instance("a", created: 1)
        let b = instance("b", created: 2)
        let c = instance("c", created: 3)
        // The order of the list must not matter, only the creation date.
        let colors = InstancePalette.assignments(for: [c, a, b])
        #expect(colors[a.id] == .blue)
        #expect(colors[b.id] == .orange)
        #expect(colors[c.id] == .green)
    }

    @Test func aColorPickedByHandIsKeptAndSkippedByAuto() {
        let a = instance("a", created: 1)
        let b = instance("b", created: 2, color: "blue")
        let c = instance("c", created: 3)
        let colors = InstancePalette.assignments(for: [a, b, c])
        #expect(colors[b.id] == .blue)
        #expect(colors[a.id] == .orange)
        #expect(colors[c.id] == .green)
    }

    @Test func theSameCreationTimeIsBrokenByTheIDSoEveryDeviceAgrees() {
        let first = instance("a", created: 5)
        let second = instance("b", created: 5)
        let one = InstancePalette.assignments(for: [first, second])
        let other = InstancePalette.assignments(for: [second, first])
        #expect(one == other)
        #expect(Set(one.values).count == 2)
    }

    @Test func thePaletteStartsOverWhenThereAreMoreInstancesThanColors() {
        let many = (0..<10).map { instance("i\($0)", created: TimeInterval($0)) }
        let colors = InstancePalette.assignments(for: many)
        #expect(colors[many[0].id] == .blue)
        #expect(colors[many[8].id] == .blue)
        #expect(colors[many[9].id] == .orange)
    }

    @Test func whenHandPickedColorsUseUpThePaletteAutoReusesIt() {
        let picks = InstancePalette.allCases.enumerated().map { instance("p\($0.offset)", created: TimeInterval($0.offset), color: $0.element.rawValue) }
        let auto = instance("auto", created: 100)
        let colors = InstancePalette.assignments(for: picks + [auto])
        #expect(colors[auto.id] == .blue)
    }

    @Test func countsReadAsSingularOrPlural() {
        #expect(CountText.text(1, singular: "shift") == "1 shift")
        #expect(CountText.text(0, singular: "shift") == "0 shifts")
        #expect(CountText.text(4, singular: "post") == "4 posts")
        #expect(CountText.text(2, singular: "entry", plural: "entries") == "2 entries")
    }

    @Test func noInstancesNoColors() {
        #expect(InstancePalette.assignments(for: []).isEmpty)
    }
}

@MainActor
struct MergedLocationTests {
    private func location(_ id: Int, name: String, instance: Instance) -> CachedLocation {
        CachedLocation(serverID: id, instanceID: instance.id, name: name, locationDescription: "", url: "https://x.test/\(id)")
    }

    @Test func sameServerAndIDIsOneLocationWithEveryInstanceName() {
        let a = Instance(name: "Account A", baseURL: "https://one.test/", apiKeyKeychainRef: "a")
        let b = Instance(name: "Account B", baseURL: "https://one.test", apiKeyKeychainRef: "b")
        let other = Instance(name: "Other", baseURL: "https://two.test", apiKeyKeychainRef: "o")
        let locations = [
            location(1, name: "Heaven", instance: a), location(1, name: "Heaven", instance: b),
            location(2, name: "Foodcourt", instance: a), location(1, name: "Heaven (other)", instance: other),
        ]
        let merged = CachedLocation.mergedAcrossServers(locations, instances: [a, b, other])
        #expect(merged.map(\.location.name) == ["Heaven", "Foodcourt", "Heaven (other)"])
        #expect(merged[0].instanceNames == ["Account A", "Account B"])
        #expect(merged[1].instanceNames == ["Account A"])
        #expect(merged[2].instanceNames == ["Other"])
        #expect(merged[0].id == locations[0].uid)
    }

    @Test func aLocationOfAnUnknownInstanceStaysAloneWithoutAName() {
        let known = Instance(name: "Known", baseURL: "https://one.test", apiKeyKeychainRef: "k")
        let stray = CachedLocation(serverID: 1, instanceID: UUID(), name: "Stray", locationDescription: "", url: "u")
        let merged = CachedLocation.mergedAcrossServers([stray], instances: [known])
        #expect(merged.count == 1)
        #expect(merged[0].instanceNames.isEmpty)
    }

    @Test func theEdgeBelongsToTheOnlyInstanceOfAnEntry() {
        #expect(InstanceEdge.name(for: ["Home"]) == "Home")
        #expect(InstanceEdge.name(for: ["Home", "Congress"]) == nil)
        #expect(InstanceEdge.name(for: []) == nil)
    }
}
