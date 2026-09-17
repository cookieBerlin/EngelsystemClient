//
//  ContentView.swift
//  EngelsystemClient Watch App Watch App
//
//  Created by Angelo Cuccato on 31.08.26.
//

import SwiftUI
import SwiftData
import EngelsystemClientKit

/// With no instance configured yet, goes straight to `WatchSettingsView` (2026-09-18,
/// at the user's request) rather than the manual-entry `WatchSetupView` — since
/// `Instance` now syncs via CloudKit unconditionally (see `ModelContainerFactory`'s
/// 2026-09-18 root-cause fix), an instance created on the iPhone should just appear
/// here on its own; showing Settings first lets the user watch `CloudSyncStatus`'s
/// footer to see whether that's actually happening, rather than being steered straight
/// into manual entry as if sync wasn't an option. `WatchSetupView` (manual entry / "Try
/// Demo Mode") is still one tap away via Settings' existing "Add Instance" button, so
/// CLAUDE.md's "Fallback" path remains fully reachable. Reactive via `@Query`: once an
/// instance exists (synced in or manually added), this automatically switches to
/// `WatchMainView` on its own.
struct ContentView: View {
    @Query(sort: \Instance.createdAt) private var instances: [Instance]

    var body: some View {
        NavigationStack {
            if instances.isEmpty {
                WatchSettingsView()
            } else {
                WatchMainView(instances: instances)
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Instance.self, inMemory: true)
}
