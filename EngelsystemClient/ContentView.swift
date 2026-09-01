//
//  ContentView.swift
//  EngelsystemClient
//
//  Created by Angelo Cuccato on 31.08.26.
//

import SwiftUI
import SwiftData
import EngelsystemClientKit

struct ContentView: View {
    @Query(sort: \Instance.createdAt) private var instances: [Instance]

    var body: some View {
        if instances.isEmpty {
            InstanceSetupView(isInitialSetup: true)
        } else {
            MainView(instances: instances)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Instance.self, inMemory: true)
}
