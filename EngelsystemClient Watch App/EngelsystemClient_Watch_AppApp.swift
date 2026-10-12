//
//  EngelsystemClient_Watch_AppApp.swift
//  EngelsystemClient Watch App
//
//  Created by Angelo Cuccato on 31.08.26.
//

import SwiftUI
import SwiftData
import EngelsystemClientKit

@main
struct EngelsystemClient_Watch_AppApp: App {
    // Instance syncs via CloudKit (same container as the iOS app), so instances added
    // on the iPhone appear here automatically; CachedShift stays local-only, a
    // per-device cache re-fetched on every sync — see ModelContainerFactory. The Watch
    // app remains standalone per its scope regardless (its own network call for
    // shifts) — WatchConnectivity (below) is only ever a fast-path *supplement* to that,
    // never a replacement (2026-09-23, "keep the Watch fresh" feature; see
    // docs/architecture.md's "Sync strategy" for the full reasoning).
    var sharedModelContainer: ModelContainer = ModelContainerFactory.makeContainer(localSchemaTypes: [
        CachedShift.self,
    ])

    // Kept as a stored property so it isn't deallocated — `WCSession.delegate` doesn't
    // keep its own strong reference. Set up in `init()`, same "safe to read
    // sharedModelContainer's already-applied default here" reasoning as
    // `BackgroundSyncScheduler.register` on the iOS side.
    private let watchConnectivityReceiver: WatchConnectivityReceiver

    init() {
        let receiver = WatchConnectivityReceiver(modelContainer: sharedModelContainer)
        receiver.activate()
        watchConnectivityReceiver = receiver
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .refreshesOnRemoteCloudKitChange(modelContext: sharedModelContainer.mainContext)
        }
        .modelContainer(sharedModelContainer)
    }
}
