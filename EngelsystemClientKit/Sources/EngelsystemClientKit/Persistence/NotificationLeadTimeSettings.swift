import Foundation
import SwiftData

/// CloudKit-backed (see CLAUDE.md's Sync strategy) — but unlike `Instance`, this
/// intentionally has one row **per platform**, not a single shared singleton.
///
/// 2026-09-22, user-requested "multiple reminders" feature: both iOS and watchOS
/// schedule their own local shift-start reminders (CLAUDE.md's Watch App Scope), and
/// the user explicitly asked for the reminder list to sync *within* a platform (an
/// iPhone and iPad on the same account should agree) but *not* across iOS and Watch —
/// you might legitimately want fewer/different reminders on your wrist than your
/// phone. `platform` is the discriminator: every iOS/iPadOS device resolves to the
/// "ios" row, every watchOS device to the "watch" row, both synced independently
/// through the same CloudKit container `Instance` already uses.
///
/// Every stored property needs a default value and `id` can't be `.unique` — same
/// CloudKit/SwiftData requirement as `Instance` (see its doc comment for the full
/// explanation).
@Model
public final class NotificationLeadTimeSettings {
    public var id: UUID = UUID()
    public var platform: String = ""
    // Comma-separated minutes, e.g. "15,60" — mirrors the plain-value storage style
    // already used elsewhere in this project (`Instance`'s fields) rather than a
    // Codable-encoded blob.
    public var leadTimesMinutesRaw: String = ""
    public var updatedAt: Date = Date()

    public init(id: UUID = UUID(), platform: String, leadTimesMinutesRaw: String) {
        self.id = id
        self.platform = platform
        self.leadTimesMinutesRaw = leadTimesMinutesRaw
        self.updatedAt = Date()
    }
}

public extension NotificationLeadTimeSettings {
    /// "ios" on iOS/iPadOS, "watch" on watchOS — resolved at compile time, so an
    /// iPhone and iPad (both the iOS target) naturally resolve to the same row and
    /// share reminders, while the Watch app resolves to its own, separate row.
    static var currentPlatform: String {
        #if os(watchOS)
        "watch"
        #else
        "ios"
        #endif
    }

    static let defaultLeadTimesMinutes = [NotificationScheduler.defaultMinutesBefore]

    var leadTimesMinutes: [Int] {
        get { Self.parseLeadTimes(leadTimesMinutesRaw) }
        set { leadTimesMinutesRaw = Self.encodeLeadTimes(newValue) }
    }

    func touch() { updatedAt = Date() }

    /// Pure parsing/encoding, kept separate so it's unit-testable without a
    /// `ModelContext`. **An empty (or malformed) string parses to `[]`, not the
    /// default list** — deliberately, even though this is also what the
    /// CloudKit-required `= ""` property default parses to. Bug found and fixed
    /// 2026-09-22 while testing: an earlier version fell back to
    /// `defaultLeadTimesMinutes` here, which meant removing a user's *last*
    /// remaining reminder immediately "bounced back" to showing the default again —
    /// there was no way to tell "never configured" apart from "deliberately cleared
    /// to zero reminders" once both are stored as the same empty string. Zero
    /// reminders is a legitimate, intentional end state (a full opt-out), so it must
    /// stay zero. `defaultLeadTimesMinutes` is applied in exactly one place instead:
    /// `resolve(for:in:)`, when creating a platform's row for the very first time.
    static func parseLeadTimes(_ raw: String) -> [Int] {
        raw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    static func encodeLeadTimes(_ minutes: [Int]) -> String {
        minutes.map(String.init).joined(separator: ",")
    }

    /// Which of the fixed presets aren't in the currently-selected list yet — backs
    /// Settings' "Add Reminder" affordance on both iOS (`Menu`) and Watch (a pushed
    /// list, `Menu` being unavailable there). A `static` pure function, shared by
    /// both `SettingsView` and `WatchSettingsView` rather than each re-deriving the
    /// same filter, and unit-testable without either.
    static func availableToAdd(
        currentlySelected: [Int],
        presets: [Int] = NotificationScheduler.availableLeadTimesInMinutes
    ) -> [Int] {
        presets.filter { !currentlySelected.contains($0) }
    }

    /// Fetches this device's own row (`currentPlatform`), creating one with the
    /// default lead time if it doesn't exist yet.
    @discardableResult
    static func resolve(in modelContext: ModelContext) -> NotificationLeadTimeSettings {
        resolve(for: currentPlatform, in: modelContext)
    }

    /// Platform-parameterized so tests can resolve the "watch" row from a plain
    /// test host without actually compiling for watchOS.
    @discardableResult
    static func resolve(for platform: String, in modelContext: ModelContext) -> NotificationLeadTimeSettings {
        var descriptor = FetchDescriptor<NotificationLeadTimeSettings>(predicate: #Predicate { $0.platform == platform })
        descriptor.fetchLimit = 1
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }
        let created = NotificationLeadTimeSettings(platform: platform, leadTimesMinutesRaw: encodeLeadTimes(defaultLeadTimesMinutes))
        modelContext.insert(created)
        try? modelContext.save()
        return created
    }
}
