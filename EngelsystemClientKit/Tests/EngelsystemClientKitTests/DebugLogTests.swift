import Foundation
import Testing
@testable import EngelsystemClientKit

/// `DebugLog.shared` is a true singleton (fire-and-forget `log(...)` hops to
/// `@MainActor` internally) — these tests call its internal `append`/`loadFromDisk`
/// directly instead of racing that hop, and each resets state via `clear()` first so
/// tests stay independent despite sharing one process-wide instance. `.serialized`
/// since they all touch the same singleton and on-disk file.
@Suite(.serialized)
@MainActor
struct DebugLogTests {
    init() {
        DebugLog.shared.clear()
        UserDefaults.standard.removeObject(forKey: DebugLog.maxEntriesUserDefaultsKey)
    }

    @Test func entryPersistedLineRoundTripsIncludingEmbeddedNewlines() {
        let entry = DebugLogEntry(level: .warning, message: "line one\nline two")
        let parsed = DebugLogEntry.parse(persistedLine: entry.persistedLine)
        #expect(parsed?.level == .warning)
        #expect(parsed?.message == "line one\nline two")
        #expect(parsed?.timestamp.timeIntervalSince1970 == entry.timestamp.timeIntervalSince1970)
    }

    @Test func parsePersistedLineReturnsNilForAnUnparsableLine() {
        #expect(DebugLogEntry.parse(persistedLine: "not a valid persisted line") == nil)
        #expect(DebugLogEntry.parse(persistedLine: "") == nil)
    }

    @Test func isEnabledDefaultsToFalseButRespectsAnExplicitValue() {
        let defaults = UserDefaults(suiteName: "DebugLogTests-\(UUID().uuidString)")!
        #expect(!DebugLog.isEnabled(in: defaults))
        defaults.set(true, forKey: DebugLog.isEnabledUserDefaultsKey)
        #expect(DebugLog.isEnabled(in: defaults))
    }

    @Test func maxEntriesFallsBackToDefaultWhenUnsetButRespectsAStoredValue() {
        let defaults = UserDefaults(suiteName: "DebugLogTests-\(UUID().uuidString)")!
        #expect(DebugLog.maxEntries(in: defaults) == DebugLog.defaultMaxEntries)
        defaults.set(1000, forKey: DebugLog.maxEntriesUserDefaultsKey)
        #expect(DebugLog.maxEntries(in: defaults) == 1000)
    }

    /// Regression coverage for the size-configurability feature itself: reducing the
    /// max below the current entry count must trim on the very next append, not
    /// require some separate "re-apply the limit" step.
    @Test func appendTrimsToTheCurrentlyConfiguredMax() {
        UserDefaults.standard.set(3, forKey: DebugLog.maxEntriesUserDefaultsKey)

        for i in 1...5 {
            DebugLog.shared.append(DebugLogEntry(level: .info, message: "entry \(i)"))
        }

        #expect(DebugLog.shared.entries.count == 3)
        #expect(DebugLog.shared.entries.map(\.message) == ["entry 3", "entry 4", "entry 5"])
    }

    /// The trimmed set must also be what's on disk — not just in memory — since a
    /// relaunch reloads from the file, not from the in-memory array.
    @Test func appendTrimsThePersistedFileToMatchTheInMemoryBuffer() {
        UserDefaults.standard.set(2, forKey: DebugLog.maxEntriesUserDefaultsKey)

        for i in 1...4 {
            DebugLog.shared.append(DebugLogEntry(level: .info, message: "entry \(i)"))
        }

        let fileText = try? String(contentsOf: DebugLog.fileURL, encoding: .utf8)
        let persistedMessages = fileText?
            .split(separator: "\n")
            .compactMap { DebugLogEntry.parse(persistedLine: String($0))?.message }
        #expect(persistedMessages == ["entry 3", "entry 4"])
    }

    /// Simulates "the app relaunched" without needing a second singleton instance —
    /// `loadFromDisk()` is exactly what `init()` calls, just invoked again on the
    /// same instance after manually seeding the file.
    @Test func loadFromDiskReadsBackPreviouslyPersistedEntries() {
        let entries = [
            DebugLogEntry(level: .info, message: "first"),
            DebugLogEntry(level: .error, message: "second"),
        ]
        let text = entries.map(\.persistedLine).joined(separator: "\n") + "\n"
        try? text.write(to: DebugLog.fileURL, atomically: true, encoding: .utf8)

        DebugLog.shared.loadFromDisk()

        #expect(DebugLog.shared.entries.map(\.message) == ["first", "second"])
        #expect(DebugLog.shared.entries.map(\.level) == [.info, .error])
    }

    @Test func clearEmptiesEntriesAndRemovesTheFile() {
        DebugLog.shared.append(DebugLogEntry(level: .info, message: "will be cleared"))
        #expect(!DebugLog.shared.entries.isEmpty)

        DebugLog.shared.clear()

        #expect(DebugLog.shared.entries.isEmpty)
        #expect(DebugLog.shared.exportText.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: DebugLog.fileURL.path))
    }

    @Test func exportTextJoinsEntriesInOrderUsingDisplayText() {
        let first = DebugLogEntry(level: .info, message: "first")
        let second = DebugLogEntry(level: .error, message: "second")
        DebugLog.shared.append(first)
        DebugLog.shared.append(second)

        #expect(DebugLog.shared.exportText == "\(first.displayText)\n\(second.displayText)")
    }
}
