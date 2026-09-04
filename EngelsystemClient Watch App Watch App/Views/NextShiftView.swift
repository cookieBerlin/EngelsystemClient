import SwiftUI
import SwiftData
import EngelsystemClientKit

/// Shows only the next upcoming shift — no full shift catalog, no news — per
/// CLAUDE.md's deliberately minimal Watch App Scope.
struct NextShiftView: View {
    let instance: Instance

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = NextShiftViewModel()
    @Query private var shifts: [CachedShift]

    init(instance: Instance) {
        self.instance = instance
        let instanceID = instance.id
        _shifts = Query(filter: #Predicate<CachedShift> { $0.instanceID == instanceID })
    }

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
                    Text("No upcoming shifts")
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
        .task { await viewModel.refresh(instance: instance, in: modelContext) }
        .refreshable { await viewModel.refresh(instance: instance, in: modelContext) }
    }
}
