import Foundation

public enum DebugLogLevel: String, Sendable {
    case info, warning, error
}

public struct DebugLogEntry: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let level: DebugLogLevel
    public let message: String

    public init(id: UUID = UUID(), timestamp: Date = Date(), level: DebugLogLevel, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
    }

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    /// Human-readable single line — used both by `DebugLogView` and as the unit
    /// joined together for "Copy to Clipboard".
    public var displayText: String {
        "\(Self.displayFormatter.string(from: timestamp)) [\(level.rawValue.uppercased())] \(message)"
    }

    /// Persisted on-disk form — tab-separated rather than the fixed-width
    /// `displayText` shape, so parsing it back on the next launch doesn't depend on
    /// brittle string-index arithmetic (a `DateFormatter` round trip, or a message
    /// that happens to contain "[", would be enough to break a fixed-width parse).
    /// Newlines within `message` are escaped so one entry always occupies exactly
    /// one line in the file.
    var persistedLine: String {
        let escapedMessage = message.replacingOccurrences(of: "\n", with: "\\n")
        return "\(timestamp.timeIntervalSince1970)\t\(level.rawValue)\t\(escapedMessage)"
    }

    /// `nil` for a line that doesn't parse (e.g. a partially-written last line after
    /// the app was killed mid-write) — dropped silently by the caller rather than
    /// crashing or showing a garbled entry.
    static func parse(persistedLine line: String) -> DebugLogEntry? {
        let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3,
              let epoch = Double(parts[0]),
              let level = DebugLogLevel(rawValue: String(parts[1]))
        else { return nil }
        let message = String(parts[2]).replacingOccurrences(of: "\\n", with: "\n")
        return DebugLogEntry(timestamp: Date(timeIntervalSince1970: epoch), level: level, message: message)
    }
}

/// In-app debug log, 2026-09-23 user-requested: the project already had `print`-only
/// diagnostics scattered across the sync/notification code (see CLAUDE.md) that were
/// only ever visible with Xcode/lldb attached — useless for diagnosing an issue on a
/// device that isn't tethered to a Mac. `DebugLog.log(...)` replaces every one of
/// those `print` calls; it always still prints internally (so the existing
/// Xcode-console workflow is completely unaffected), and *additionally* stores the
/// entry in memory + on disk when the user has turned logging on in Settings
/// (iOS-only — see `DebugLogView`/`SettingsView`; the Watch has no UI for this, so it
/// silently never enables and `log(...)` there is a print-only no-op, same as before).
///
/// Persists to a plain-text file in the Caches directory (excluded from backups,
/// appropriate for ephemeral diagnostics) — written to on **every** call, not just
/// batched at some later point. This matters specifically for the background-sync
/// use case: a `BGAppRefreshTask` can be killed by the system the moment its time
/// budget runs out, so anything only held in memory could be lost before ever
/// reaching disk if writes were deferred.
@MainActor
@Observable
public final class DebugLog {
    public static let shared = DebugLog()

    public private(set) var entries: [DebugLogEntry] = []

    public nonisolated static let isEnabledUserDefaultsKey = "debugLoggingEnabled"
    public nonisolated static let maxEntriesUserDefaultsKey = "debugLogMaxEntries"
    public nonisolated static let defaultMaxEntries = 500
    public nonisolated static let availableMaxEntryCounts = [100, 500, 1000, 5000]

    /// Whether logging is on when nobody ever touched the switch. **On during the beta** so testers have data without
    /// doing anything; to be decided again before the first App Store release (probably off — `docs/release.md`).
    public nonisolated static let defaultEnabled = true

    public nonisolated static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        (defaults.object(forKey: isEnabledUserDefaultsKey) as? Bool) ?? defaultEnabled
    }

    /// Falls back to `defaultMaxEntries` both when nothing's been chosen yet (`0`,
    /// `UserDefaults.integer`'s own default-for-missing-key) and for any stored
    /// value that isn't one of `availableMaxEntryCounts` — never lets the cap end up
    /// at `0`, which would otherwise mean "store nothing, ever" for a state that's
    /// meant to represent "no preference set".
    public nonisolated static func maxEntries(in defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.integer(forKey: maxEntriesUserDefaultsKey)
        return stored > 0 ? stored : defaultMaxEntries
    }

    // Internal, not private: lets EngelsystemClientKitTests write/read the file and
    // trigger a reload directly, without a race against `log`'s fire-and-forget
    // `Task` hop — see `DebugLogTests` for why that would otherwise be awkward to
    // test through the public `log(...)` entry point alone.
    static let fileURL: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("debug-log.txt")
    }()

    private init() {
        loadFromDisk()
    }

    func loadFromDisk() {
        guard let data = try? Data(contentsOf: Self.fileURL), let text = String(data: data, encoding: .utf8) else { return }
        let loaded = text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { DebugLogEntry.parse(persistedLine: String($0)) }
        entries = Array(loaded.suffix(Self.maxEntries()))
    }

    /// Callable from anywhere — sync or async code, any actor/thread — without
    /// `await`, matching how `print` was called at every one of the sites this
    /// replaces. Always prints; only stores (memory + disk) when enabled, checked
    /// up front so a disabled log doesn't even pay for spinning up a `Task`.
    public nonisolated static func log(_ message: String, level: DebugLogLevel = .info) {
        print("[DebugLog] [\(level.rawValue.uppercased())] \(message)")
        guard isEnabled() else { return }
        Task { @MainActor in
            shared.append(DebugLogEntry(level: level, message: message))
        }
    }

    // Internal, not private — see `fileURL`'s comment for why tests call this
    // directly instead of going through `log(...)`.
    func append(_ entry: DebugLogEntry) {
        entries.append(entry)
        let max = Self.maxEntries()
        let didTrim = entries.count > max
        if didTrim {
            entries.removeFirst(entries.count - max)
        }
        appendToDisk(entry, rewriteAll: didTrim)
    }

    /// Cheap append for the common case; only rewrites the whole file (from the
    /// now-trimmed in-memory buffer) on the rarer occasions storage actually needs
    /// trimming, rather than reading/rewriting the file on every single log call.
    private func appendToDisk(_ entry: DebugLogEntry, rewriteAll: Bool) {
        if rewriteAll {
            let text = entries.map(\.persistedLine).joined(separator: "\n") + "\n"
            try? text.write(to: Self.fileURL, atomically: true, encoding: .utf8)
            return
        }
        let line = entry.persistedLine + "\n"
        let data = Data(line.utf8)
        if let handle = try? FileHandle(forWritingTo: Self.fileURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: Self.fileURL)
        }
    }

    public func clear() {
        entries.removeAll()
        try? FileManager.default.removeItem(at: Self.fileURL)
    }

    /// Backs the "Copy to Clipboard" button.
    public var exportText: String {
        entries.map(\.displayText).joined(separator: "\n")
    }
}
