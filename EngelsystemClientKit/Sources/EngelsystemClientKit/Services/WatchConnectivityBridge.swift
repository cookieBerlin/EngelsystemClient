import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Sends a lightweight "shifts changed, please resync" nudge from iOS to a paired Watch —
/// 2026-09-23, user-requested "keep the Watch data as fresh as possible" feature. This is
/// a deliberate, explicit exception to CLAUDE.md's original "don't use WatchConnectivity
/// as the primary sync mechanism" rule, added as a fast *supplement* only — the Watch's
/// own independent sync (its own API call, no relay) remains the mechanism that makes it
/// work with no iPhone nearby at all; this bridge only ever makes an already-working Watch
/// notice a change sooner while it's actually paired/reachable. See
/// `docs/architecture.md` ("Sync strategy") for the full writeup, and
/// `Instance.shiftsChangedAt` for the CloudKit-based counterpart that covers the
/// not-currently-paired case.
///
/// Lives in `EngelsystemClientKit`, not the iOS app target, specifically so
/// `AppSyncCoordinator` (shared, platform-agnostic Kit code) can call
/// `notifyShiftsChanged()` directly and unconditionally — it's a safe no-op on watchOS
/// and on macOS (this package's `swift test` platform, where `WatchConnectivity` can't
/// even be imported), so callers never need a platform check of their own.
///
/// No payload beyond a timestamp is sent: receiving this just means "something changed,
/// resync everything active" — the same thing the Watch's own app-start sync already
/// does, so there's no need for per-instance/per-shift detail here.
public enum WatchConnectivityBridge {
    /// Activates the session on iOS — call once at app launch (mirrors
    /// `BackgroundSyncScheduler.register`'s "call from App init" pattern). A session
    /// needs *some* delegate assigned before `activate()`, even though this feature is
    /// send-only from iOS's side; `IOSSessionDelegate` below exists purely to satisfy
    /// that requirement (plus the documented "reactivate on deactivate" pattern for
    /// multi-Watch support). No-op on watchOS/macOS — the Watch side manages its own
    /// session/delegate directly in the Watch app target, since *it* needs to actually
    /// react to incoming data (see `WatchConnectivityReceiver`).
    public static func activate() {
        #if os(iOS) && canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = IOSSessionDelegate.shared
        WCSession.default.activate()
        #endif
    }

    /// Best-effort — silently does nothing if there's no paired Watch, the Watch app
    /// isn't installed, or the session isn't activated yet. Callers never need to check
    /// for success; the CloudKit-based `Instance.shiftsChangedAt` signal is the fallback
    /// that still gets the Watch caught up whenever it next syncs on its own.
    public static func notifyShiftsChanged() {
        #if os(iOS) && canImport(WatchConnectivity)
        let session = WCSession.default
        guard WCSession.isSupported(),
              session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled
        else {
            DebugLog.log("WatchConnectivityBridge: not paired/installed/activated — skipping nudge")
            return
        }
        do {
            try session.updateApplicationContext(["shiftsChangedAt": Date().timeIntervalSinceReferenceDate])
            DebugLog.log("WatchConnectivityBridge: sent shifts-changed nudge")
        } catch {
            DebugLog.log("WatchConnectivityBridge: failed to send nudge: \(error)", level: .error)
        }
        #endif
    }
}

#if os(iOS) && canImport(WatchConnectivity)
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
#endif
