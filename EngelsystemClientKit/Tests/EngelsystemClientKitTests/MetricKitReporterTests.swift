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

    @Test func persistAppendsJSONLinesAndExportTextJoinsThemBack() {
        MetricKitReporter.shared.persist(jsonLine: #"{"payload":1}"#)
        MetricKitReporter.shared.persist(jsonLine: #"{"payload":2}"#)

        let exported = MetricKitReporter.shared.exportText()
        #expect(exported == "{\"payload\":1}\n{\"payload\":2}\n")
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
