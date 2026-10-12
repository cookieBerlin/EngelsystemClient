//
//  EngelsystemClientApp.swift
//  EngelsystemClient
//
//  Created by Angelo Cuccato on 31.08.26.
//

import SwiftUI
import SwiftData
import EngelsystemClientKit

@main
struct EngelsystemClientApp: App {
    // Instance syncs via CloudKit (same container as the Watch app); the Cached* models
    // stay local-only, per-device caches of API data — see ModelContainerFactory.
    var sharedModelContainer: ModelContainer = ModelContainerFactory.makeContainer(localSchemaTypes: [
        CachedShift.self,
        CachedNews.self,
        CachedUser.self,
        CachedWorklog.self,
        CachedAngelTypeMembership.self,
        CachedLocation.self,
    ])

    // `BGTaskScheduler.register` must run before the app finishes launching (Apple's
    // documented requirement) — `init()` is the earliest hook available without an
    // AppDelegate. Struct property defaults (`sharedModelContainer` above) are already
    // applied by the time a custom `init()`'s body runs, so it's safe to read here.
    //
    // No `scenePhase`-triggered reschedule needed (an earlier version of this had
    // one, to catch up with a CloudKit-merged interval change made on the Watch) —
    // the polling interval is a plain per-device `DeviceSyncPreferences` value now
    // (2026-09-22, reverted the same day: Watch background execution isn't
    // implemented at all, so syncing/displaying the interval there was pointless —
    // see CLAUDE.md), and `SettingsView` already reschedules directly the moment it
    // changes. Cold launch is the only time this needs to run.
    init() {
        BackgroundSyncScheduler.register(modelContainer: sharedModelContainer)
        BackgroundSyncScheduler.scheduleNext()
        // 2026-09-23, "keep the Watch fresh" feature — see WatchConnectivityBridge and
        // docs/architecture.md's "Sync strategy".
        WatchConnectivityBridge.activate()
        // 2026-10-09, user-requested crash/diagnostics reporting via MetricKit — see
        // MetricKitReporter and docs/features.md.
        MetricKitReporter.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .refreshesOnRemoteCloudKitChange(modelContext: sharedModelContainer.mainContext)
        }
        .modelContainer(sharedModelContainer)
    }
}
