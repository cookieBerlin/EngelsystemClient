//
//  ContentView.swift
//  EngelsystemClient Watch App Watch App
//
//  Created by Angelo Cuccato on 31.08.26.
//

import SwiftUI
import SwiftData
import EngelsystemClientKit

struct ContentView: View {
    // Single-instance by design (see CLAUDE.md's Watch App Scope) — no instance
    // switcher here, unlike the iOS app.
    @Query(sort: \Instance.createdAt) private var instances: [Instance]

    var body: some View {
        NavigationStack {
            if let instance = instances.first {
                NextShiftView(instance: instance)
            } else {
                WatchSetupView()
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Instance.self, inMemory: true)
}
