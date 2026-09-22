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
    // app is still standalone per its scope either way (its own network call for
    // shifts, no WatchConnectivity relay).
    var sharedModelContainer: ModelContainer = ModelContainerFactory.makeContainer(localSchemaTypes: [
        CachedShift.self,
    ])

    var body: some Scene {
        WindowGroup {
            ContentView()
                .refreshesOnRemoteCloudKitChange(modelContext: sharedModelContainer.mainContext)
        }
        .modelContainer(sharedModelContainer)
    }
}
