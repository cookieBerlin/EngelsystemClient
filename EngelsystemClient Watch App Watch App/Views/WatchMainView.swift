import SwiftUI
import EngelsystemClientKit

/// Root view once at least one instance is configured. 2026-09-17 multi-active-instance
/// redesign (CLAUDE.md): any number of instances can be active at once
/// (`Instance.isActive`), so this no longer resolves a single active instance —
/// `NextShiftView` receives every active instance and shows the nearest upcoming shift
/// across all of them (still exactly one shift, per the Watch's minimal scope).
struct WatchMainView: View {
    let instances: [Instance]

    private var activeInstances: [Instance] { instances.filter(\.isActive) }

    var body: some View {
        NextShiftView(instances: activeInstances)
    }
}
