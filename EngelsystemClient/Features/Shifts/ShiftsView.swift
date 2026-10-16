import SwiftUI
import SwiftData
import Combine
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
    @State private var collapsedInstances: Set<UUID> = []
    @Environment(\.instanceColors) private var instanceColors
    @AppStorage(MultiInstanceDisplayMode.userDefaultsKey)
    private var displayModeRaw: String = MultiInstanceDisplayMode.merged.rawValue
    @AppStorage(ShiftTimeFilter.userDefaultsKey) private var filterRaw: String = ShiftTimeFilter.default.rawValue
    @AppStorage(ShiftSortOrder.userDefaultsKey) private var sortRaw: String = ShiftSortOrder.default.rawValue
    /// "Now" for the Past/Today/Upcoming split; refreshed every minute (and so also across midnight).
    @State private var now = Date()
    @Query(sort: \CachedShift.startsAt) private var allShifts: [CachedShift]
    // Unfiltered, same fetch-everything-and-filter-in-Swift pattern as `allShifts` —
    // backs the location link below (2026-09-23, user-requested).
    @Query private var allLocations: [CachedLocation]
    // Own account's cached profile, for finding the own entry in a shift's team (only the own
    // profile has an email address).
    @Query private var allUsers: [CachedUser]

    /// A single active instance renders the same regardless of the display-mode
    /// setting, so it's always treated as `.merged` (no pointless picker/sections).
    private var displayMode: MultiInstanceDisplayMode {
        InstanceScope.displayMode(raw: displayModeRaw, instanceCount: instances.count)
    }

    private var filter: ShiftTimeFilter { .stored(raw: filterRaw) }
    private var sortOrder: ShiftSortOrder { .stored(raw: sortRaw) }

    /// Every cached shift of the active instances, whatever the filter says.
    private var allInstanceShifts: [CachedShift] { InstanceScope.filter(allShifts, to: instances, instanceID: \.instanceID) }

    private var shifts: [CachedShift] { CachedShift.filtered(allInstanceShifts, by: filter, now: now) }

    private var switcherInstance: Instance? {
        InstanceScope.switcherInstance(in: instances, selected: selectedInstanceID)
    }

    private func instanceName(for shift: CachedShift) -> String? {
        InstanceScope.instanceName(withID: shift.instanceID, in: instances)
    }

    private func instance(for shift: CachedShift) -> Instance? {
        InstanceScope.instance(withID: shift.instanceID, in: instances)
    }

    /// The location a shift's `locationID` refers to — `nil` when Locations hasn't
    /// synced yet, or the shift's location was since removed server-side (2026-09-23,
    /// user-requested "link the location name to its description"). `ShiftRow` falls
    /// back to a plain, non-linked label in that case rather than linking to nothing.
    private func location(for shift: CachedShift) -> CachedLocation? {
        InstanceScope.location(for: shift, in: allLocations)
    }

    private func ownUserID(for shift: CachedShift) -> Int? {
        allUsers.first { $0.instanceID == shift.instanceID && $0.email != nil }?.serverID
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
                                InstanceSection(
                                    instance: instance,
                                    countText: CountText.text(instanceShifts.count, singular: "shift"),
                                    collapsed: $collapsedInstances
                                ) {
                                    ForEach(CachedShift.groupedByDay(instanceShifts, order: sortOrder), id: \.day) { group in
                                        SubheadingRow(title: dateHeaderText(group.day))
                                        ForEach(group.shifts) { shift in
                                            // `instance` is this ForEach's own loop variable (already exactly the
                                            // shift's owning instance), unlike the `instance(for:)` helper used by
                                            // the .merged/.switcher rows.
                                            ShiftRow(shift: shift, location: location(for: shift), instance: instance, ownUserID: ownUserID(for: shift))
                                        }
                                    }
                                }
                            }
                        }
                        if shifts.isEmpty && !viewModel.isLoading {
                            emptyState
                        }
                    }

                    SyncTimestampFooter(date: allInstanceShifts.map(\.cachedAt).max())
                }
                .listStyle(.plain)
                .toolbar {
                    if viewModel.isLoading {
                        ToolbarItem { ProgressView() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        filterMenu
                    }
                }
                .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
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
            ForEach(CachedShift.groupedByDay(shifts, order: sortOrder), id: \.day) { group in
                Section(dateHeaderText(group.day)) {
                    ForEach(group.shifts) { shift in
                        ShiftRow(
                            shift: shift,
                            location: location(for: shift),
                            instance: instance(for: shift),
                            ownUserID: ownUserID(for: shift),
                            instanceName: labeled ? instanceName(for: shift) : nil
                        )
                        .instanceEdge(named: labeled ? instanceName(for: shift) : nil, colors: instanceColors)
                    }
                }
            }
        }
    }

    private func dateHeaderText(_ day: Date) -> String {
        InstanceScope.dayHeaderText(day)
    }

    /// "Show" (time filter) and "Sort" in one menu, like the News filter; the symbol is filled when either
    /// differs from the default.
    private var filterMenu: some View {
        Menu {
            Section("Show") {
                Picker("Show", selection: Binding(get: { filter }, set: { filterRaw = $0.rawValue })) {
                    ForEach(ShiftTimeFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            }
            Section("Sort") {
                Picker("Sort", selection: Binding(get: { sortOrder }, set: { sortRaw = $0.rawValue })) {
                    ForEach(ShiftSortOrder.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            }
        } label: {
            Label(
                "Filter",
                systemImage: filter == .default && sortOrder == .default
                    ? "line.3.horizontal.decrease.circle"
                    : "line.3.horizontal.decrease.circle.fill"
            )
        }
        .accessibilityIdentifier("shiftFilterMenu")
    }

    /// Distinguishes "no shifts at all" from "the filter hides all of them".
    @ViewBuilder
    private var emptyState: some View {
        if ShiftListing.filterHidesEverything(allCount: allInstanceShifts.count, shownCount: shifts.count) {
            ContentUnavailableView {
                Label("No Matching Shifts", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("No shifts match the current filter.")
            } actions: {
                Button("Show All") { filterRaw = ShiftTimeFilter.all.rawValue }
            }
        } else {
            ContentUnavailableView(
                "No Shifts",
                systemImage: "calendar",
                description: Text("You don't have any shifts yet.")
            )
        }
    }
}

private struct ShiftRow: View {
    let shift: CachedShift
    /// The location `shift.locationID` refers to — `nil` when Locations hasn't synced
    /// yet, or the location was since removed server-side (2026-09-23,
    /// user-requested "link the location name to its description"). Falls back to a
    /// plain, non-linked label in that case rather than linking to nothing.
    var location: CachedLocation?
    var instance: Instance?
    var ownUserID: Int?
    var instanceName: String?

    @State private var showsDetail = false
    @State private var showsLocation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // The detail page and the location are separate buttons: two `NavigationLink`s in one
            // `List` row would fire together (same quirk as the news row), so both navigate by state.
            Button {
                showsDetail = true
            } label: {
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
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("shiftRow")
            // COMPAT(#1711): without readable locations the name stays plain text.
            if let location, ServerCapabilities.shared.isAvailable(.locationsList, for: shift.instanceID) {
                Button {
                    showsLocation = true
                } label: {
                    Label(location.name, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .navigationDestination(isPresented: $showsLocation) {
                    LocationDetailView(location: location, instance: instance)
                }
            } else if let locationName = shift.locationName {
                Label(locationName, systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .navigationDestination(isPresented: $showsDetail) {
            ShiftDetailView(shift: shift, location: location, instance: instance, ownUserID: ownUserID)
        }
    }
}

/// Small per-row label identifying which active instance an item in a merged list came
/// from — used across Shifts/News/Profile in `MultiInstanceDisplayMode.merged`.
struct InstanceBadge: View {
    let name: String

    @Environment(\.instanceColors) private var colors

    var body: some View {
        Text(name)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(colors.color(named: name)))
    }
}
