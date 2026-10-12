import Foundation

/// Subscribes to Apple's MetricKit for crash/hang/performance diagnostics during
/// TestFlight testing (2026-10-09, user-requested) — consistent with this app's
/// "no analytics, no third-party tracking" stance: everything MetricKit delivers is
/// on-device only, and this reporter never transmits anything anywhere automatically.
/// Decided data-handling model: **local + manual export** — a short human-readable
/// summary of each payload goes through the existing `DebugLog` (visible in Settings'
/// debug log, same as every other diagnostic in this app); the full payload is
/// additionally persisted to disk so a tester can explicitly export/share it (e.g. to
/// attach to a bug report email) via `exportText()`.
///
/// iOS-only (`#if os(iOS)`), like Locations/Messages — no diagnostics UI on the Watch.
/// `MXMetricManagerSubscriber`'s conformance is entirely behind that same guard (plus
/// `canImport(MetricKit)`, which is false for this package's `swift test` platform,
/// plain macOS — MetricKit isn't available there at all) so the rest of this type
/// still compiles and is testable on macOS; only the actual subscription is a no-op
/// there.
public final class MetricKitReporter: NSObject {
    public static let shared = MetricKitReporter()

    // Internal, not private — lets tests write/read the file directly and call
    // `persist(jsonLine:)`/`exportText()`/`clear()` without a real `MXDiagnosticPayload`
    // (which has no public initializer, so the actual `didReceive` delegate methods
    // can't be exercised from a test at all — same fundamental limitation as
    // `UNNotificationSettings` elsewhere in this project).
    static let fileURL: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("metrickit-diagnostics.jsonl")
    }()

    /// Retention limits (2026-10-12): stored payloads older than `maxAge` are dropped, and
    /// the oldest are dropped first once the file exceeds `maxBytes`. The newest entry is
    /// always kept, even if it alone is larger than `maxBytes`, so a fresh crash report is
    /// never lost to the limit.
    static let maxAge: TimeInterval = 30 * 24 * 60 * 60
    static let maxBytes = 1_000_000

    private override init() {
        super.init()
    }

    /// Everything persisted so far — one JSON payload per line (JSON Lines), so a new
    /// delivery can always be appended cheaply rather than needing to re-parse and
    /// re-serialize an aggregate array. Backs the manual "Export Diagnostics" action.
    /// `nil` when nothing's been received/persisted yet, so the UI can disable the
    /// export action instead of offering to share an empty file.
    public func exportText() -> String? {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty
        else { return nil }
        return text
    }

    public func clear() {
        try? FileManager.default.removeItem(at: Self.fileURL)
    }

    /// The pure "what does this payload actually contain" summarizing logic behind the
    /// `DebugLog` line written for each `MXDiagnosticPayload` — split out so it's
    /// unit-testable without a real payload (see the `fileURL` comment above for why
    /// that's not possible at all here).
    static func summarize(crashCount: Int, hangCount: Int, cpuExceptionCount: Int, diskWriteExceptionCount: Int) -> String {
        var parts: [String] = []
        if crashCount > 0 { parts.append("\(crashCount) crash") }
        if hangCount > 0 { parts.append("\(hangCount) hang") }
        if cpuExceptionCount > 0 { parts.append("\(cpuExceptionCount) CPU exception") }
        if diskWriteExceptionCount > 0 { parts.append("\(diskWriteExceptionCount) disk write exception") }
        guard !parts.isEmpty else {
            return "MetricKitReporter: received a diagnostic payload with no reportable diagnostics"
        }
        return "MetricKitReporter: received \(parts.joined(separator: ", ")) diagnostic(s)"
    }

    /// Appends one payload, wrapped as `{"receivedAt": <ISO 8601>, "payload": <payload JSON>}`
    /// (one line per delivery), then applies the retention limits. Deliveries are rare
    /// (at most daily, or once at the next launch after a crash), so rewriting the
    /// file when pruning is cheap.
    func persist(jsonLine: String, now: Date = Date()) {
        let stamp = ISO8601DateFormatter().string(from: now)
        let line = "{\"receivedAt\":\"\(stamp)\",\"payload\":\(jsonLine)}"
        var lines = storedLines()
        lines.append(line)
        write(Self.retained(lines, now: now, maxAge: Self.maxAge, maxBytes: Self.maxBytes))
    }

    /// Applies the retention limits to what's already on disk (called at launch, so old
    /// entries expire even if no new delivery arrives).
    func prune(now: Date = Date()) {
        let lines = storedLines()
        guard !lines.isEmpty else { return }
        write(Self.retained(lines, now: now, maxAge: Self.maxAge, maxBytes: Self.maxBytes))
    }

    /// Pure retention logic: drops lines older than `maxAge` (or without a readable
    /// `receivedAt`, e.g. written by an older build), then drops the oldest lines until the
    /// total size fits `maxBytes`, always keeping at least the newest surviving line.
    static func retained(_ lines: [String], now: Date, maxAge: TimeInterval, maxBytes: Int) -> [String] {
        let formatter = ISO8601DateFormatter()
        var kept = lines.filter { line in
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let stamp = object["receivedAt"] as? String,
                  let date = formatter.date(from: stamp)
            else { return false }
            return now.timeIntervalSince(date) <= maxAge
        }
        func size(_ l: [String]) -> Int { l.reduce(0) { $0 + $1.utf8.count + 1 } }
        while kept.count > 1 && size(kept) > maxBytes {
            kept.removeFirst()
        }
        return kept
    }

    private func storedLines() -> [String] {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let text = String(data: data, encoding: .utf8)
        else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    private func write(_ lines: [String]) {
        guard !lines.isEmpty else {
            clear()
            return
        }
        let text = lines.joined(separator: "\n") + "\n"
        try? text.data(using: .utf8)?.write(to: Self.fileURL, options: .atomic)
    }
}
