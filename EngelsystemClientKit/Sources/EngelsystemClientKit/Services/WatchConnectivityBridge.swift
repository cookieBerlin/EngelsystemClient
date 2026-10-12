import Foundation

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
/// The bits of `WCSession` the bridge needs, as plain Foundation types, so the decisions
/// below compile and are tested on every platform (`swift test` runs on macOS, where
/// `WatchConnectivity` can't even be imported). The real iOS implementation and the
/// no-op implementation for other platforms live in `SystemWatchSession.swift`.
protocol WatchSessionControlling {
    var isSupported: Bool { get }
    var isActivated: Bool { get }
    var isPaired: Bool { get }
    var isWatchAppInstalled: Bool { get }
    func activate()
    func sendShiftsChanged(at timestamp: TimeInterval) throws
}

public enum WatchConnectivityBridge {
    /// Activates the session — a no-op unless the session is supported (iOS with
    /// WatchConnectivity). The public no-argument `activate()` lives in
    /// `SystemWatchSession.swift` and passes the real session.
    static func activate(using session: WatchSessionControlling) {
        guard session.isSupported else { return }
        session.activate()
    }

    /// Best-effort — silently does nothing if there's no paired Watch, the Watch app
    /// isn't installed, or the session isn't activated yet. Callers never need to check
    /// for success; the CloudKit-based `Instance.shiftsChangedAt` signal is the fallback
    /// that still gets the Watch caught up whenever it next syncs on its own.
    static func notifyShiftsChanged(using session: WatchSessionControlling, now: Date) {
        guard session.isSupported else { return }
        guard session.isActivated, session.isPaired, session.isWatchAppInstalled else {
            DebugLog.log("WatchConnectivityBridge: not paired/installed/activated — skipping nudge")
            return
        }
        do {
            try session.sendShiftsChanged(at: now.timeIntervalSinceReferenceDate)
            DebugLog.log("WatchConnectivityBridge: sent shifts-changed nudge")
        } catch {
            DebugLog.log("WatchConnectivityBridge: failed to send nudge: \(error)", level: .error)
        }
    }
}
