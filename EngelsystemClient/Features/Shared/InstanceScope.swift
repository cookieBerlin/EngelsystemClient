import Foundation
import EngelsystemClientKit

/// The instance-scoping logic every multi-instance screen (Shifts, News, Profile,
/// Locations, Messages) used to repeat inline in its view: which display mode applies,
/// which items belong to the active instances, which instance the switcher shows, and
/// lookups by `instanceID`. Pure functions, so the screens' view files only lay things
/// out (see ADR 0010) and this logic is covered by unit tests.
enum InstanceScope {
    /// A single active instance renders the same regardless of the display-mode
    /// setting, so it's always treated as `.merged` (no pointless picker/sections);
    /// an unknown stored value also falls back to `.merged`.
    static func displayMode(raw: String, instanceCount: Int) -> MultiInstanceDisplayMode {
        guard instanceCount > 1 else { return .merged }
        return MultiInstanceDisplayMode.stored(raw: raw)
    }

    /// The items that belong to one of the given (active) instances.
    static func filter<Item>(_ items: [Item], to instances: [Instance], instanceID: KeyPath<Item, UUID>) -> [Item] {
        let ids = Set(instances.map(\.id))
        return items.filter { ids.contains($0[keyPath: instanceID]) }
    }

    /// The instance the switcher currently shows: the selected one, else the first.
    static func switcherInstance(in instances: [Instance], selected: UUID?) -> Instance? {
        instance(withID: selected, in: instances) ?? instances.first
    }

    static func instance(withID id: UUID?, in instances: [Instance]) -> Instance? {
        instances.first { $0.id == id }
    }

    static func instanceName(withID id: UUID, in instances: [Instance]) -> String? {
        instance(withID: id, in: instances)?.name
    }

    /// The location a shift's `locationID` refers to — `nil` when Locations hasn't
    /// synced yet or the location was since removed server-side.
    static func location(for shift: CachedShift, in locations: [CachedLocation]) -> CachedLocation? {
        locations.first { $0.instanceID == shift.instanceID && $0.serverID == shift.locationID }
    }

    /// "Today" / "Tomorrow" / a long weekday-month-day date for a day header.
    static func dayHeaderText(_ day: Date, calendar: Calendar = .current, now: Date = Date()) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(day, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }
        return day.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    /// One instance's conversations, newest first.
    static func conversations(for instance: Instance, in byInstanceID: [UUID: [Conversation]]) -> [Conversation] {
        (byInstanceID[instance.id] ?? []).sorted { $0.latestMessage.createdAt > $1.latestMessage.createdAt }
    }

    /// Every instance's conversations merged into one list, newest first.
    static func allConversations(
        instances: [Instance], byInstanceID: [UUID: [Conversation]]
    ) -> [(instance: Instance, conversation: Conversation)] {
        instances.flatMap { instance in
            conversations(for: instance, in: byInstanceID).map { (instance: instance, conversation: $0) }
        }.sorted { $0.conversation.latestMessage.createdAt > $1.conversation.latestMessage.createdAt }
    }
}
