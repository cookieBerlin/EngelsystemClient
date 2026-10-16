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
    /// The Watch app is running and can take a live message.
    var isReachable: Bool { get }
    func activate()
    /// Replaces the application context the Watch sees (always the complete dictionary).
    func updateContext(_ context: [String: Any]) throws
    func sendMessage(_ message: [String: Any])
}

/// What happened to a request for the Watch's log.
public enum WatchLogRequestOutcome: Equatable, Sendable {
    /// The Watch app is reachable: the request went out at once (and is also kept for later).
    case sentLive
    /// The Watch is not reachable now: the request waits and is answered when the Watch app runs.
    case queued
    /// No paired Watch with the app installed.
    case unavailable
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
    static func notifyShiftsChanged(using session: WatchSessionControlling, now: Date, state: WatchContextState = WatchContextState()) {
        guard session.isSupported else { return }
        guard session.isActivated, session.isPaired, session.isWatchAppInstalled else {
            DebugLog.log("WatchConnectivityBridge: not paired/installed/activated — skipping nudge")
            return
        }
        state.noteShiftsChanged(at: now.timeIntervalSinceReferenceDate)
        do {
            try session.updateContext(state.dictionary)
            DebugLog.log("WatchConnectivityBridge: sent shifts-changed nudge")
        } catch {
            DebugLog.log("WatchConnectivityBridge: failed to send nudge: \(error)", level: .error)
        }
    }

    private static func isReady(_ session: WatchSessionControlling) -> Bool {
        session.isSupported && session.isActivated && session.isPaired && session.isWatchAppInstalled
    }

    /// Asks the Watch to send its debug log (2026-10-16): live when the Watch app is reachable and, in any case, kept
    /// in the application context so a Watch that is not running answers when it next does. Each request has its own
    /// id, the Watch answers each id once.
    static func requestWatchLog(
        using session: WatchSessionControlling, id: String = UUID().uuidString, state: WatchContextState = WatchContextState()
    ) -> WatchLogRequestOutcome {
        guard isReady(session) else { return .unavailable }
        state.noteLogRequest(id: id)
        do {
            try session.updateContext(state.dictionary)
        } catch {
            DebugLog.log("WatchConnectivityBridge: failed to queue the log request: \(error)", level: .error)
            return .unavailable
        }
        guard session.isReachable else { return .queued }
        session.sendMessage([WatchLogKeys.requestLog: id])
        return .sentLive
    }

    /// The logging wish the iPhone last sent to the Watch.
    public static func desiredWatchLogging() -> LoggingSwitch? {
        WatchContextState().loggingSwitch
    }

    /// Switches the Watch's debug logging (2026-10-16): the wish is kept in the application context; the Watch applies
    /// it when it is newer than its own last change and reports its state back. Returns whether the wish was handed over.
    @discardableResult
    static func setWatchLogging(
        _ isOn: Bool, using session: WatchSessionControlling, now: Date = Date(), state: WatchContextState = WatchContextState()
    ) -> Bool {
        guard isReady(session) else { return false }
        state.noteLoggingSwitch(LoggingSwitch(isOn: isOn, changedAt: now.timeIntervalSince1970))
        do {
            try session.updateContext(state.dictionary)
            return true
        } catch {
            DebugLog.log("WatchConnectivityBridge: failed to send the logging switch: \(error)", level: .error)
            return false
        }
    }
}
