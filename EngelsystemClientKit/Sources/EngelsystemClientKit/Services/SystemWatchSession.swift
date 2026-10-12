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

    func activate() {
        WCSession.default.delegate = IOSSessionDelegate.shared
        WCSession.default.activate()
    }

    func sendShiftsChanged(at timestamp: TimeInterval) throws {
        try WCSession.default.updateApplicationContext(["shiftsChangedAt": timestamp])
    }
}

/// Minimal delegate purely to satisfy `WCSession`'s activation requirement — this
/// feature doesn't need iOS to react to anything incoming. `sessionDidDeactivate`
/// re-activates per Apple's documented pattern for switching between multiple paired
/// Watches.
private final class IOSSessionDelegate: NSObject, WCSessionDelegate {
    static let shared = IOSSessionDelegate()

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            DebugLog.log("WatchConnectivityBridge: activation failed: \(error)", level: .error)
        } else {
            DebugLog.log("WatchConnectivityBridge: activated (state: \(activationState.rawValue), paired: \(session.isPaired), watchAppInstalled: \(session.isWatchAppInstalled))")
        }
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
    func activate() {}
    func sendShiftsChanged(at timestamp: TimeInterval) throws {}
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
}
