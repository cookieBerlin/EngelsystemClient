import Foundation
#if canImport(MetricKit)
import MetricKit
#endif

/// Thin adapter between Apple's MetricKit and `MetricKitReporter` — kept in its own file
/// because `MXMetricPayload`/`MXDiagnosticPayload` have no public initializer and MetricKit
/// only exists on iOS, so none of this can run in unit tests. All decisions (summaries,
/// persistence, retention, export) live in `MetricKitReporter` and are tested there.
/// Excluded from the coverage gate (standing approval for thin adapters, owner, 2026-10-12).
extension MetricKitReporter {
    /// Call once at app launch.
    public func activate() {
        prune()
        #if os(iOS) && canImport(MetricKit)
        MXMetricManager.shared.add(self)
        DebugLog.log("MetricKitReporter: subscribed to MXMetricManager")
        #else
        DebugLog.log("MetricKitReporter: MetricKit unavailable on this platform — not subscribing")
        #endif
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
