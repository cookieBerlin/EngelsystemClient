import Foundation
import EngelsystemClientKit

/// Backs the Watch's Diagnostics page (2026-10-16): its own debug logging switch and "Send Log to iPhone". Sending is
/// only ever the user's tap (or a request from the iPhone, handled in `WatchConnectivityReceiver`); nothing is sent
/// automatically.
@Observable
@MainActor
final class WatchDiagnosticsViewModel {
    private let responder: WatchLogResponder
    private let defaults: UserDefaults
    private let lastSentKey = "watchLogLastSentAt"

    /// What the page says below the button after a tap.
    private(set) var statusText: String?
    private(set) var lastSentAt: Date?

    init(
        responder: WatchLogResponder = WatchLogResponder(sender: WatchSystemSender()),
        defaults: UserDefaults = .standard
    ) {
        self.responder = responder
        self.defaults = defaults
        lastSentAt = defaults.object(forKey: lastSentKey) as? Date
    }

    /// Turns the Watch's logging on or off and remembers when (so the newer change wins against the iPhone's).
    func setLogging(_ isOn: Bool, now: Date = Date()) {
        DebugLog.setEnabled(isOn, at: now, in: defaults)
        responder.reportState(now: now)
    }

    /// Hands the log to the connection. The iPhone receives it when it can ("Queued").
    func sendLog(now: Date = Date()) {
        switch responder.sendLog(now: now) {
        case .queued:
            lastSentAt = now
            defaults.set(now, forKey: lastSentKey)
            statusText = "Queued. Open the iPhone app to receive it."
        case .noLog:
            statusText = "Nothing logged yet."
        }
    }

    /// "Last sent 12 min ago", nil before the first send.
    func lastSentText(now: Date = Date()) -> String? {
        lastSentAt.map { "Last sent " + $0.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)) }
    }
}
