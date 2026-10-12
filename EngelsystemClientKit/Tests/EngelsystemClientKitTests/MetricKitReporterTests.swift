import Foundation
import Testing
@testable import EngelsystemClientKit

/// `MXDiagnosticPayload`/`MXMetricPayload` have no public initializer, so the actual
/// `didReceive` delegate methods can't be exercised from a test at all (same
/// fundamental limitation as `UNNotificationSettings` elsewhere in this project) —
/// these tests cover the pure summarizing logic and the persist/export/clear plumbing
/// directly instead, via `MetricKitReporter`'s internal entry points. `.serialized`
/// since they all touch the same singleton's on-disk file.
@Suite(.serialized)
struct MetricKitReporterTests {
    init() {
        MetricKitReporter.shared.clear()
    }

    @Test func exportTextIsNilWhenNothingHasBeenPersistedYet() {
        #expect(MetricKitReporter.shared.exportText() == nil)
    }

    @Test func persistWrapsEachPayloadWithAReceivedTimestampOnePerLine() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        MetricKitReporter.shared.persist(jsonLine: #"{"payload":1}"#, now: now)
        MetricKitReporter.shared.persist(jsonLine: #"{"payload":2}"#, now: now)

        let lines = try #require(MetricKitReporter.shared.exportText())
            .split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        let first = try #require(
            try JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any]
        )
        #expect(first["receivedAt"] as? String == ISO8601DateFormatter().string(from: now))
        #expect((first["payload"] as? [String: Int]) == ["payload": 1])
    }

    @Test func retainedDropsEntriesOlderThanTheMaxAge() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func line(_ daysAgo: Double, _ id: Int) -> String {
            let stamp = ISO8601DateFormatter().string(from: now.addingTimeInterval(-daysAgo * 86_400))
            return "{\"receivedAt\":\"\(stamp)\",\"payload\":{\"id\":\(id)}}"
        }
        let lines = [line(40, 1), line(29, 2), line(1, 3)]
        let kept = MetricKitReporter.retained(lines, now: now, maxAge: 30 * 86_400, maxBytes: 1_000_000)
        #expect(kept == [lines[1], lines[2]])
    }

    @Test func retainedDropsLinesWithoutAReadableTimestamp() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let kept = MetricKitReporter.retained(
            [#"{"payload":1}"#, "not json"], now: now, maxAge: 86_400, maxBytes: 1_000_000
        )
        #expect(kept.isEmpty)
    }

    @Test func retainedDropsTheOldestFirstWhenOverTheSizeLimit() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let stamp = ISO8601DateFormatter().string(from: now)
        let lines = (1...4).map { "{\"receivedAt\":\"\(stamp)\",\"payload\":{\"id\":\($0)}}" }
        let oneLine = lines[0].utf8.count + 1
        let kept = MetricKitReporter.retained(lines, now: now, maxAge: 86_400, maxBytes: oneLine * 2)
        #expect(kept == [lines[2], lines[3]])
    }

    @Test func retainedAlwaysKeepsTheNewestEntryEvenIfItAloneIsTooLarge() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let stamp = ISO8601DateFormatter().string(from: now)
        let lines = (1...2).map { "{\"receivedAt\":\"\(stamp)\",\"payload\":{\"id\":\($0)}}" }
        let kept = MetricKitReporter.retained(lines, now: now, maxAge: 86_400, maxBytes: 1)
        #expect(kept == [lines[1]])
    }

    @Test func pruneExpiresOldEntriesOnDisk() {
        let old = Date(timeIntervalSince1970: 1_800_000_000)
        MetricKitReporter.shared.persist(jsonLine: #"{"payload":1}"#, now: old)
        #expect(MetricKitReporter.shared.exportText() != nil)

        MetricKitReporter.shared.prune(now: old.addingTimeInterval(MetricKitReporter.maxAge + 60))
        #expect(MetricKitReporter.shared.exportText() == nil)
    }

    @Test func clearRemovesEverythingPersisted() {
        MetricKitReporter.shared.persist(jsonLine: #"{"payload":1}"#)
        #expect(MetricKitReporter.shared.exportText() != nil)

        MetricKitReporter.shared.clear()
        #expect(MetricKitReporter.shared.exportText() == nil)
    }

    @Test func summarizeDescribesEveryNonZeroDiagnosticKind() {
        let summary = MetricKitReporter.summarize(
            crashCount: 2, hangCount: 1, cpuExceptionCount: 0, diskWriteExceptionCount: 3
        )
        #expect(summary == "MetricKitReporter: received 2 crash, 1 hang, 3 disk write exception diagnostic(s)")
    }

    @Test func summarizeHandlesAllZeroCounts() {
        let summary = MetricKitReporter.summarize(
            crashCount: 0, hangCount: 0, cpuExceptionCount: 0, diskWriteExceptionCount: 0
        )
        #expect(summary == "MetricKitReporter: received a diagnostic payload with no reportable diagnostics")
    }

    @Test func summarizeHandlesExactlyOneNonZeroKind() {
        let summary = MetricKitReporter.summarize(
            crashCount: 0, hangCount: 0, cpuExceptionCount: 1, diskWriteExceptionCount: 0
        )
        #expect(summary == "MetricKitReporter: received 1 CPU exception diagnostic(s)")
    }

    @Test func activateDoesNotCrashRegardlessOfPlatformAvailability() {
        // No assertion beyond "doesn't throw/crash" — on macOS (this test's own
        // platform), MetricKit isn't available at all, so this exercises the
        // no-op `#else` branch; the real iOS subscription path can't be verified
        // outside a real device/simulator run.
        MetricKitReporter.shared.activate()
    }
}
