import SwiftUI
import SwiftData
import EngelsystemClientKit

/// 2026-09-17 multi-active-instance redesign (CLAUDE.md): `instances` is every
/// currently active instance, aggregated per the user's `MultiInstanceDisplayMode`
/// preference (merged/switcher/sectioned) rather than a single fixed instance.
struct ShiftsView: View {
    let instances: [Instance]
    /// Shared with `MainView`, so this screen's own pull-to-refresh shows the same
    /// `SyncProgressBanner` the app-start/main-page sync does (2026-09-22,
    /// user-requested: "the banner should show for every pull-to-refresh, not just
    /// the app-start sync").
    let syncStatus: MainSyncStatus
    var onUnauthorized: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ShiftsViewModel()
    @State private var selectedInstanceID: UUID?
    @AppStorage(MultiInstanceDisplayMode.userDefaultsKey)
    private var displayModeRaw: String = MultiInstanceDisplayMode.merged.rawValue
    @Query(sort: \CachedShift.startsAt) private var allShifts: [CachedShift]

    /// A single active instance renders the same regardless of the display-mode
    /// setting, so it's always treated as `.merged` (no pointless picker/sections).
    private var displayMode: MultiInstanceDisplayMode {
        guard instances.count > 1 else { return .merged }
        return MultiInstanceDisplayMode(rawValue: displayModeRaw) ?? .merged
    }

    private var instanceIDs: Set<UUID> { Set(instances.map(\.id)) }
    private var shifts: [CachedShift] { allShifts.filter { instanceIDs.contains($0.instanceID) } }

    private var switcherInstance: Instance? {
        instances.first(where: { $0.id == selectedInstanceID }) ?? instances.first
    }

    private func instanceName(for shift: CachedShift) -> String? {
        instances.first(where: { $0.id == shift.instanceID })?.name
    }

    var body: some View {
        Group {
            if instances.isEmpty {
                ContentUnavailableView(
                    "No Active Instance",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Activate an instance in Settings to see its shifts.")
                )
            } else {
                List {
                    if let errorMessage = viewModel.errorMessage {
                        Section {
                            ErrorBanner(message: errorMessage)
                        }
                        .listRowInsets(EdgeInsets())
                    }

                    switch displayMode {
                    case .merged:
                        shiftRows(shifts, labeled: true)
                    case .switcher:
                        InstancePicker(instances: instances, selection: $selectedInstanceID)
                            .listRowSeparator(.hidden)
                        shiftRows(shifts.filter { $0.instanceID == switcherInstance?.id }, labeled: false)
                    case .sectioned:
                        ForEach(instances) { instance in
                            let instanceShifts = shifts.filter { $0.instanceID == instance.id }
                            if !instanceShifts.isEmpty {
                                Section(instance.name) {
                                    // A `Section` can't nest inside another `Section` in a
                                    // plain `List`, so date sub-groups here are a styled
                                    // header row rather than a real `Section` (unlike
                                    // .merged/.switcher below, which aren't already
                                    // sectioned by instance and can use real ones).
                                    ForEach(CachedShift.groupedByDay(instanceShifts), id: \.day) { group in
                                        Text(dateHeaderText(group.day))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        ForEach(group.shifts) { shift in
                                            ShiftRow(shift: shift)
                                        }
                                    }
                                }
                            }
                        }
                        if shifts.isEmpty && !viewModel.isLoading {
                            emptyState
                        }
                    }
                }
                .listStyle(.plain)
                .toolbar {
                    if viewModel.isLoading {
                        ToolbarItem { ProgressView() }
                    }
                }
                // No `.task`-on-appear sync (2026-09-22, user-requested, to reduce
                // server load — see CLAUDE.md's polling-interval/background-sync
                // feature): this screen now only refreshes via an explicit
                // pull-to-refresh, plus whatever the app-start/background sync
                // already wrote to `CachedShift` before this screen was even opened.
                .refreshable {
                    await syncStatus.run(statusText: "Shifts") {
                        await viewModel.refresh(instances: instances, in: modelContext)
                        return viewModel.errorMessage == nil
                    }
                }
                .onChange(of: viewModel.isUnauthorized) { _, isUnauthorized in
                    if isUnauthorized { onUnauthorized() }
                }
            }
        }
        .navigationTitle("Shifts")
    }

    /// Shifts grouped into one `Section` per calendar day — a shift row on its own only
    /// shows a time, not a date, so the day header is what actually conveys it.
    @ViewBuilder
    private func shiftRows(_ shifts: [CachedShift], labeled: Bool) -> some View {
        if shifts.isEmpty && !viewModel.isLoading {
            emptyState
        } else {
            ForEach(CachedShift.groupedByDay(shifts), id: \.day) { group in
                Section(dateHeaderText(group.day)) {
                    ForEach(group.shifts) { shift in
                        ShiftRow(shift: shift, instanceName: labeled ? instanceName(for: shift) : nil)
                    }
                }
            }
        }
    }

    private func dateHeaderText(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInTomorrow(day) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Shifts",
            systemImage: "calendar",
            description: Text("You don't have any shifts yet.")
        )
    }
}

private struct ShiftRow: View {
    let shift: CachedShift
    var instanceName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(shift.title)
                    .font(.headline)
                if let instanceName {
                    Spacer()
                    InstanceBadge(name: instanceName)
                }
            }
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

/// Small per-row label identifying which active instance an item in a merged list came
/// from — used across Shifts/News/Profile in `MultiInstanceDisplayMode.merged`.
struct InstanceBadge: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.blue.opacity(0.15)))
    }
}
