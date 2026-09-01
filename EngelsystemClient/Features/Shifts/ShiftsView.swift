import SwiftUI
import SwiftData
import EngelsystemClientKit

struct ShiftsView: View {
    let instance: Instance

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ShiftsViewModel()
    @Query private var shifts: [CachedShift]

    init(instance: Instance) {
        self.instance = instance
        let instanceID = instance.id
        _shifts = Query(
            filter: #Predicate<CachedShift> { $0.instanceID == instanceID },
            sort: \CachedShift.startsAt
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if let errorMessage = viewModel.errorMessage {
                ErrorBanner(message: errorMessage)
            }

            if shifts.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "No Shifts",
                    systemImage: "calendar",
                    description: Text("You don't have any shifts yet.")
                )
            } else {
                List(shifts) { shift in
                    ShiftRow(shift: shift)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Shifts")
        .toolbar {
            if viewModel.isLoading {
                ToolbarItem { ProgressView() }
            }
        }
        .refreshable { await viewModel.refresh(instance: instance, in: modelContext) }
        .task { await viewModel.refresh(instance: instance, in: modelContext) }
    }
}

private struct ShiftRow: View {
    let shift: CachedShift

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(shift.title)
                .font(.headline)
            Text(shift.formattedTimeRange())
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let locationName = shift.locationName {
                Label(locationName, systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
