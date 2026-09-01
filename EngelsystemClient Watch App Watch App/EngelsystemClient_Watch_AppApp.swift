//
//  EngelsystemClient_Watch_AppApp.swift
//  EngelsystemClient Watch App Watch App
//
//  Created by Angelo Cuccato on 31.08.26.
//

import SwiftUI
import SwiftData
import EngelsystemClientKit

@main
struct EngelsystemClient_Watch_App_Watch_AppApp: App {
    // Local-only for now, like the iOS app's container — CloudKit sync between the
    // two targets needs the entitlements described in CLAUDE.md, which require an
    // Apple Developer team not available in this environment. The Watch app is
    // standalone per its scope either way (its own network call, own local setup).
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Instance.self, CachedShift.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
