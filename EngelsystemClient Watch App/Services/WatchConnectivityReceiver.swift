import Foundation
import SwiftData
import WatchConnectivity
import EngelsystemClientKit

/// Receives the "shifts changed" nudge sent from the iPhone via `WatchConnectivityBridge`
/// — 2026-09-23, "keep the Watch fresh" feature. Lives in the Watch app target, not
/// `EngelsystemClientKit`: it needs to react by calling into `WatchShiftsSyncCoordinator`,
/// which is Watch-app-specific (WidgetKit/complication concerns don't belong in the
/// platform-agnostic Kit package) — unlike `WatchConnectivityBridge`'s send side, which
/// has no such dependency and stays in Kit so `AppSyncCoordinator` can call it directly.
///
/// `WCSessionDelegate`'s `session(_:didReceiveApplicationContext:)` isn't `async` (it has
/// to match the protocol's synchronous signature) and fires on an arbitrary queue, not
/// necessarily the main thread — it just hops to `@MainActor` and fires-and-forgets
/// `handleApplicationContext()`, which holds the actual (`async`, directly awaitable)
/// reaction logic. `WatchConnectivityReceiverTests` calls `handleApplicationContext()`
/// directly rather than the delegate method, so it can `await` the effect deterministically
/// instead of racing the fire-and-forget `Task` — the same testability shape `DebugLog.log`
/// already uses for the same reason.
final class WatchConnectivityReceiver: NSObject, WCSessionDelegate {
    private let modelContainer: ModelContainer
    private let syncCoordinator: WatchShiftsSyncCoordinator
    private let logResponder: WatchLogResponder
    private let defaults: UserDefaults
    private let handledShiftsChangeKey = "watchLastHandledShiftsChangedAt"

    init(
        modelContainer: ModelContainer,
        syncCoordinator: WatchShiftsSyncCoordinator = .shared,
        logResponder: WatchLogResponder = WatchLogResponder(sender: WatchSystemSender()),
        defaults: UserDefaults = .standard
    ) {
        self.modelContainer = modelContainer
        self.syncCoordinator = syncCoordinator
        self.logResponder = logResponder
        self.defaults = defaults
    }

    /// Call once at app launch — sets itself as the session delegate (required before
    /// activation) and activates. No-op if `WCSession` isn't supported on this device.
    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            DebugLog.log("WatchConnectivityReceiver: activation failed: \(error)", level: .error)
        } else {
            DebugLog.log("WatchConnectivityReceiver: activated (state: \(activationState.rawValue))")
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DebugLog.log("WatchConnectivityReceiver: received a context from the iPhone")
        Task { @MainActor in
            await handleApplicationContext(applicationContext)
        }
    }

    /// A live message from the iPhone (the Watch app is reachable): the request for the debug log.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            handleMessage(message)
        }
    }

    @MainActor
    func handleMessage(_ message: [String: Any]) {
        logResponder.handleMessage(message)
    }

    /// Reacts to the iPhone's context: the debug log parts (a request, the logging switch) and — only when the
    /// shifts-changed timestamp is new, or there is none — a resync of the active instances.
    @MainActor
    func handleApplicationContext(_ context: [String: Any] = [:], handleNotifications: Bool = true) async {
        logResponder.handleContext(context)
        let shiftsChangedAt = context["shiftsChangedAt"] as? Double
        if let shiftsChangedAt, defaults.object(forKey: handledShiftsChangeKey) as? Double == shiftsChangedAt { return }
        if let shiftsChangedAt { defaults.set(shiftsChangedAt, forKey: handledShiftsChangeKey) }
        await syncCoordinator.refreshActiveInstances(in: modelContainer.mainContext, handleNotifications: handleNotifications)
    }
}
