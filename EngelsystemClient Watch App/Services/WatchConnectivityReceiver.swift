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

    init(modelContainer: ModelContainer, syncCoordinator: WatchShiftsSyncCoordinator = .shared) {
        self.modelContainer = modelContainer
        self.syncCoordinator = syncCoordinator
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
        DebugLog.log("WatchConnectivityReceiver: received shifts-changed nudge — resyncing")
        Task { @MainActor in
            await handleApplicationContext()
        }
    }

    @MainActor
    func handleApplicationContext(handleNotifications: Bool = true) async {
        await syncCoordinator.refreshActiveInstances(in: modelContainer.mainContext, handleNotifications: handleNotifications)
    }
}
