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
