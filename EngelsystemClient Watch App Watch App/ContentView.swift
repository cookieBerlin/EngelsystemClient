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
    @Query(sort: \Instance.createdAt) private var instances: [Instance]

    var body: some View {
        NavigationStack {
            if instances.isEmpty {
                WatchSetupView()
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
