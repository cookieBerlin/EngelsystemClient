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

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = NextShiftViewModel()
    @Query private var allShifts: [CachedShift]

    init(instances: [Instance]) {
        self.instances = instances
    }

    private var instanceIDs: Set<UUID> { Set(instances.map(\.id)) }
    private var shifts: [CachedShift] { allShifts.filter { instanceIDs.contains($0.instanceID) } }
    private var nextShift: CachedShift? { CachedShift.nextShift(from: shifts) }

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
                if viewModel.isLoading {
                    ProgressView()
                } else if let lastUpdated = viewModel.lastUpdated {
                    Text("Updated \(lastUpdated.formatted(date: .omitted, time: .shortened))")
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
        .navigationTitle("Next Shift")
        .task { await viewModel.refresh(instances: instances, in: modelContext) }
        .refreshable { await viewModel.refresh(instances: instances, in: modelContext) }
    }
}
