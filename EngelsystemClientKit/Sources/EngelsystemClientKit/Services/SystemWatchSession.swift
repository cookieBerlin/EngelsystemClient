import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Thin adapter over the real `WCSession` (iOS) — kept in its own file because the system
/// session can't be driven from unit tests. On other platforms (watchOS, macOS) the session
/// reports itself as unsupported, so the bridge is a safe no-op there and callers never
/// need a platform check of their own. All decisions live in `WatchConnectivityBridge`,
/// which is tested through `WatchSessionControlling`. Excluded from the coverage gate
/// (standing approval for thin adapters, owner, 2026-10-12).
#if os(iOS) && canImport(WatchConnectivity)
struct SystemWatchSession: WatchSessionControlling {
    var isSupported: Bool { WCSession.isSupported() }
    var isActivated: Bool { WCSession.default.activationState == .activated }
    var isPaired: Bool { WCSession.default.isPaired }
    var isWatchAppInstalled: Bool { WCSession.default.isWatchAppInstalled }
    var isReachable: Bool { WCSession.default.isReachable }

    func activate() {
        WCSession.default.delegate = IOSSessionDelegate.shared
        WCSession.default.activate()
    }

    func updateContext(_ context: [String: Any]) throws {
        try WCSession.default.updateApplicationContext(context)
    }

    func sendMessage(_ message: [String: Any]) {
        WCSession.default.sendMessage(message, replyHandler: nil) { error in
            DebugLog.log("WatchConnectivityBridge: live message failed: \(error)", level: .warning)
        }
    }
}

/// The iPhone's session delegate: activation, and the Watch's debug logs (2026-10-16) — a received file is stored
/// (the system deletes it when the callback returns, so it is moved right here) and the Watch's reports are
/// remembered. `sessionDidDeactivate` re-activates per Apple's documented pattern for switching between multiple
/// paired Watches.
private final class IOSSessionDelegate: NSObject, WCSessionDelegate {
    static let shared = IOSSessionDelegate()

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            DebugLog.log("WatchConnectivityBridge: activation failed: \(error)", level: .error)
        } else {
            DebugLog.log("WatchConnectivityBridge: activated (state: \(activationState.rawValue), paired: \(session.isPaired), watchAppInstalled: \(session.isWatchAppInstalled))")
        }
    }
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let stored = WatchLogInbox().receiveFile(at: file.fileURL)
        DebugLog.log("WatchConnectivityBridge: received a Watch log (stored: \(stored))")
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        WatchLogInbox().receiveReport(applicationContext)
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
#else
struct SystemWatchSession: WatchSessionControlling {
    var isSupported: Bool { false }
    var isActivated: Bool { false }
    var isPaired: Bool { false }
    var isWatchAppInstalled: Bool { false }
    var isReachable: Bool { false }
    func activate() {}
    func updateContext(_ context: [String: Any]) throws {}
    func sendMessage(_ message: [String: Any]) {}
}
#endif

public extension WatchConnectivityBridge {
    /// Activates the session on iOS — call once at app launch (mirrors
    /// `BackgroundSyncScheduler.register`'s "call from App init" pattern). No-op on
    /// watchOS/macOS — the Watch side manages its own session/delegate directly in the
    /// Watch app target (see `WatchConnectivityReceiver`).
    static func activate() {
        activate(using: SystemWatchSession())
    }

    static func notifyShiftsChanged() {
        notifyShiftsChanged(using: SystemWatchSession(), now: Date())
    }

    /// Asks the paired Watch for its debug log (see `requestWatchLog(using:id:state:)`).
    static func requestWatchLog() -> WatchLogRequestOutcome {
        requestWatchLog(using: SystemWatchSession())
    }

    /// Switches the Watch's debug logging from the iPhone.
    @discardableResult
    static func setWatchLogging(_ isOn: Bool) -> Bool {
        setWatchLogging(isOn, using: SystemWatchSession())
    }
}
