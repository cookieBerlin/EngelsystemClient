import SwiftUI
import SwiftData
import EngelsystemClientKit

/// Shows only the next upcoming shift — no full shift catalog, no news — per
/// CLAUDE.md's deliberately minimal Watch App Scope. Since the 2026-09-17
/// multi-active-instance redesign, `instances` is every currently active instance
/// (`Instance.isActive`) — still exactly one shift shown, but it's the nearest upcoming
/// one across all of them, not a single pre-selected instance.
struct NextShiftView: View {
    let instances: [Instance]
    /// Set by `WatchMainView` while its own app-start sync is running (2026-09-22) —
    /// purely a "something is happening" indicator; the shift content itself updates
    /// reactively via `@Query` regardless of which code path wrote it.
    var isAppStartSyncing: Bool = false

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = NextShiftViewModel()
    // Debug-only launch argument (a no-op in Release): opens Settings on launch for the screenshot script.
    @State private var isShowingSettings = DemoSeeding.shouldOpenSettings(arguments: ProcessInfo.processInfo.arguments)
    @Query private var allShifts: [CachedShift]

    init(instances: [Instance], isAppStartSyncing: Bool = false) {
        self.instances = instances
        self.isAppStartSyncing = isAppStartSyncing
    }

    private var instanceIDs: Set<UUID> { Set(instances.map(\.id)) }
    private var shifts: [CachedShift] { allShifts.filter { instanceIDs.contains($0.instanceID) } }
    private var nextShift: CachedShift? { CachedShift.nextShift(from: shifts) }
    /// 2026-09-23, user-requested, matching iOS's new Shifts/News/Profile footer:
    /// the freshest `cachedAt` across the active instance(s)' shifts — unlike the
    /// `viewModel.lastUpdated` this replaced, this also reflects `WatchMainView`'s
    /// silent app-start sync, not just an explicit pull-to-refresh on this view
    /// (`lastUpdated` was only ever set from this view's own `.refreshable`, so it
    /// stayed `nil` until the user manually pulled to refresh at least once).
    private var lastSyncedAt: Date? { shifts.map(\.cachedAt).max() }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                if let nextShift {
                    Text(nextShift.title)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text(nextShift.formattedTimeRange())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let locationName = nextShift.locationName {
                        Label(locationName, systemImage: "mappin.and.ellipse")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if !viewModel.isLoading {
                    Text(instances.isEmpty ? "No active instance" : "No upcoming shifts")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Sync status display (CLAUDE.md Watch App Scope).
                if viewModel.isLoading || isAppStartSyncing {
                    ProgressView()
                    if isAppStartSyncing {
                        Text("Syncing…")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                } else if let lastSyncedAt {
                    Text("Last Synced: \(lastSyncedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // A plain in-content row rather than a toolbar item: watchOS's compact
                // navigation bar doesn't reliably render a bare `ToolbarItem` here, so
                // this is the standard, robust watchOS pattern for reaching a secondary
                // screen.
                NavigationLink {
                    WatchSettingsView()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .navigationDestination(isPresented: $isShowingSettings) { WatchSettingsView() }
        .navigationTitle("Next Shift")
        // No `.task`-on-appear sync (2026-09-22) — `WatchMainView` now owns the
        // app-start sync; this view only refreshes via an explicit pull-to-refresh.
        .refreshable { await viewModel.refresh(instances: instances, in: modelContext) }
    }
}
