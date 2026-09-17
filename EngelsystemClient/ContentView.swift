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
    @State private var isShowingLaunchScreen = true

    /// See `LaunchScreenView` — a fixed branding moment, not a gate on real async work.
    static let launchScreenDuration: Duration = .seconds(1.2)

    var body: some View {
        ZStack {
            if instances.isEmpty {
                InstanceSetupView(isInitialSetup: true)
            } else {
                MainView(instances: instances)
            }

            if isShowingLaunchScreen {
                LaunchScreenView()
                    .transition(.opacity)
            }
        }
        .task {
            try? await Task.sleep(for: Self.launchScreenDuration)
            withAnimation {
                isShowingLaunchScreen = false
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Instance.self, inMemory: true)
}
