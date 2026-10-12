import Foundation
#if canImport(MetricKit)
import MetricKit
#endif

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

    private override init() {
        super.init()
    }

    /// Call once at app launch.
    public func activate() {
        #if os(iOS) && canImport(MetricKit)
        MXMetricManager.shared.add(self)
        DebugLog.log("MetricKitReporter: subscribed to MXMetricManager")
        #else
        DebugLog.log("MetricKitReporter: MetricKit unavailable on this platform — not subscribing")
        #endif
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

    /// Cheap append-only write, same shape as `DebugLog`'s own disk persistence —
    /// deliveries are rare enough (at most daily, or once at the next launch after a
    /// crash) that there's no need for the trim-on-overflow logic `DebugLog` has for
    /// its much more frequent log entries.
    func persist(jsonLine: String) {
        let line = jsonLine + "\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: Self.fileURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: Self.fileURL)
        }
    }
}

#if os(iOS) && canImport(MetricKit)
extension MetricKitReporter: MXMetricManagerSubscriber {
    public func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            DebugLog.log("MetricKitReporter: received a metric payload")
            if let json = String(data: payload.jsonRepresentation(), encoding: .utf8) {
                persist(jsonLine: json)
            }
        }
    }

    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let summary = Self.summarize(
                crashCount: payload.crashDiagnostics?.count ?? 0,
                hangCount: payload.hangDiagnostics?.count ?? 0,
                cpuExceptionCount: payload.cpuExceptionDiagnostics?.count ?? 0,
                diskWriteExceptionCount: payload.diskWriteExceptionDiagnostics?.count ?? 0
            )
            DebugLog.log(summary, level: .warning)
            if let json = String(data: payload.jsonRepresentation(), encoding: .utf8) {
                persist(jsonLine: json)
            }
        }
    }
}
#endif
