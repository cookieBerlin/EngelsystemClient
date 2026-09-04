import SwiftUI
import EngelsystemClientKit

/// Root view once at least one instance is configured — resolves the active instance
/// the same way the iOS app's `MainView` does (`@AppStorage("activeInstanceID")`,
/// falling back to the first instance), now that the Watch app supports switching
/// between multiple instances via `WatchSettingsView`.
struct WatchMainView: View {
    @AppStorage("activeInstanceID") private var activeInstanceIDString: String = ""

    let instances: [Instance]

    /// There's always at least one instance while `WatchMainView` is shown (see
    /// `ContentView`); falls back to the first instance if the stored active ID
    /// doesn't match any of them.
    private var activeInstance: Instance {
        instances.first(where: { $0.id.uuidString == activeInstanceIDString }) ?? instances[0]
    }

    var body: some View {
        NextShiftView(instance: activeInstance)
            .onAppear { activateFirstInstanceIfNeeded() }
    }

    private func activateFirstInstanceIfNeeded() {
        guard activeInstanceIDString.isEmpty, let first = instances.first else { return }
        activeInstanceIDString = first.id.uuidString
    }
}
