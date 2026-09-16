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
    ])

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
