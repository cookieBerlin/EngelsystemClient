import Foundation
import WatchConnectivity
import EngelsystemClientKit

/// Thin adapter over the real `WCSession` on the Watch (2026-10-16): hands the debug log file to the connection and
/// publishes the Watch's state to the iPhone. All decisions live in `WatchLogResponder` (Kit, tested through
/// `WatchLogSending`). Excluded from the coverage gate (standing approval for thin adapters over system APIs).
struct WatchSystemSender: WatchLogSending {
    func transferFile(_ url: URL, metadata: [String: Any]) {
        guard WCSession.isSupported() else { return }
        WCSession.default.transferFile(url, metadata: metadata)
    }

    func sendReport(_ report: [String: Any]) throws {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        try WCSession.default.updateApplicationContext(report)
    }
}
