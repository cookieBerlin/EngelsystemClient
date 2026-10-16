import SwiftUI
import Testing
import EngelsystemClientKit
@testable import EngelsystemClient

@MainActor
struct InstanceColorsTests {
    @Test func everyPaletteColorMapsToASystemColor() {
        let colors = InstancePalette.allCases.map(\.color)
        #expect(colors == [.blue, .orange, .green, .purple, .pink, .teal, .red, .indigo])
    }

    @Test func colorsAreFoundByIDAndByNameWithABlueFallback() {
        let home = Instance(name: "Home", baseURL: "https://h.test", apiKeyKeychainRef: "h")
        home.createdAt = Date(timeIntervalSince1970: 1)
        let congress = Instance(name: "Congress", baseURL: "https://c.test", apiKeyKeychainRef: "c")
        congress.createdAt = Date(timeIntervalSince1970: 2)
        congress.colorKey = "red"
        let colors = InstanceColors(instances: [home, congress])
        #expect(colors.color(for: congress.id) == .red)
        #expect(colors.color(named: "Congress") == .red)
        #expect(colors.color(for: home.id) == .blue)
        #expect(colors.color(for: UUID()) == .blue)
        #expect(colors.color(named: "Unknown") == .blue)
    }

    @Test func twoInstancesWithTheSameNameShareTheFirstOnesColor() {
        let first = Instance(name: "Same", baseURL: "https://1.test", apiKeyKeychainRef: "1")
        first.createdAt = Date(timeIntervalSince1970: 1)
        first.colorKey = "green"
        let second = Instance(name: "Same", baseURL: "https://2.test", apiKeyKeychainRef: "2")
        second.createdAt = Date(timeIntervalSince1970: 2)
        second.colorKey = "pink"
        let colors = InstanceColors(instances: [first, second])
        #expect(colors.color(named: "Same") == .green)
        #expect(InstanceColors() == InstanceColors(instances: []))
    }

    @Test func theEnvironmentDefaultHasNoInstances() {
        var environment = EnvironmentValues()
        #expect(environment.instanceColors == InstanceColors())
        environment.instanceColors = InstanceColors(instances: [Instance(name: "A", baseURL: "https://a.test", apiKeyKeychainRef: "a")])
        #expect(environment.instanceColors != InstanceColors())
    }
}

@MainActor
struct ConversationEntryTests {
    /// User ids repeat across instances: two instances with the same user must not share a row identity
    /// (they were drawn as the same row twice in the merged Messages list).
    @Test func theSameUserOnTwoInstancesIsTwoRows() {
        let sender = Reference(id: 7, name: "U7")
        let message = Message(
            id: 1, text: "t", sender: sender, receiver: Reference(id: 0, name: "me"),
            read: true, createdAt: Date(timeIntervalSince1970: 1), updatedAt: nil)
        let conversation = Conversation(otherUser: sender, latestMessage: message, unreadMessages: 0)
        let a = Instance(name: "A", baseURL: "https://a.test", apiKeyKeychainRef: "a")
        let b = Instance(name: "B", baseURL: "https://b.test", apiKeyKeychainRef: "b")
        let first = ConversationEntry(instance: a, conversation: conversation)
        let second = ConversationEntry(instance: b, conversation: conversation)
        #expect(first.id != second.id)
        #expect(first.id == ConversationEntry(instance: a, conversation: conversation).id)
    }
}
