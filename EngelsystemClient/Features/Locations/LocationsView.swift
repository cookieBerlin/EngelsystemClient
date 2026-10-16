import SwiftUI
import SwiftData
import EngelsystemClientKit

/// 2026-09-23, user-requested: browse an instance's locations (rooms), each linking to
/// a detail screen — also what a shift's location name links to (`ShiftsView`).
/// `instances` is every currently active instance, aggregated per
/// `MultiInstanceDisplayMode` — see `ShiftsView`/`NewsView` for the shared pattern.
struct LocationsView: View {
    let instances: [Instance]
    /// Shared with `MainView` — see `ShiftsView`'s matching property for why.
    let syncStatus: MainSyncStatus
    var onUnauthorized: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = LocationsViewModel()
    @State private var selectedInstanceID: UUID?
    @State private var collapsedInstances: Set<UUID> = []
    @Environment(\.instanceColors) private var instanceColors
    @AppStorage(MultiInstanceDisplayMode.userDefaultsKey)
    private var displayModeRaw: String = MultiInstanceDisplayMode.merged.rawValue
    @Query private var allLocations: [CachedLocation]

    private var displayMode: MultiInstanceDisplayMode {
        InstanceScope.displayMode(raw: displayModeRaw, instanceCount: instances.count)
    }

    private var activeInstanceLocations: [CachedLocation] { InstanceScope.filter(allLocations, to: instances, instanceID: \.instanceID) }

    private var switcherInstance: Instance? {
        InstanceScope.switcherInstance(in: instances, selected: selectedInstanceID)
    }

    /// The `Instance` a given cached location actually came from — needed to resolve
    /// the right credential for `LocationDetailView`'s own live refresh, since
    /// `CachedLocation` itself only carries a plain `instanceID`, not a live reference.
    private func instance(for location: CachedLocation) -> Instance? {
        InstanceScope.instance(withID: location.instanceID, in: instances)
    }

    var body: some View {
        Group {
            if instances.isEmpty {
                ContentUnavailableView(
                    "No Active Instance",
                    systemImage: "mappin.and.ellipse",
                    description: Text("Activate an instance in Settings to see its locations.")
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
                        // The same room of two accounts on one server is one entry listing both instances.
                        mergedLocationRows(CachedLocation.mergedAcrossServers(
                            CachedLocation.sortedByName(activeInstanceLocations), instances: instances))
                    case .switcher:
                        InstancePicker(instances: instances, selection: $selectedInstanceID)
                            .listRowSeparator(.hidden)
                        let filtered = activeInstanceLocations.filter { $0.instanceID == switcherInstance?.id }
                        locationRows(CachedLocation.sortedByName(filtered))
                    case .sectioned:
                        ForEach(instances) { instance in
                            let instanceLocations = CachedLocation.sortedByName(activeInstanceLocations.filter { $0.instanceID == instance.id })
                            if !instanceLocations.isEmpty {
                                InstanceSection(
                                    instance: instance,
                                    countText: CountText.text(instanceLocations.count, singular: "location"),
                                    collapsed: $collapsedInstances
                                ) {
                                    ForEach(instanceLocations) { location in
                                        LocationRow(location: location, instance: instance)
                                    }
                                }
                            }
                        }
                        if activeInstanceLocations.isEmpty && !viewModel.isLoading {
                            emptyState
                        }
                    }

                    SyncTimestampFooter(date: activeInstanceLocations.map(\.cachedAt).max())
                }
                .listStyle(.plain)
                .toolbar {
                    if viewModel.isLoading {
                        ToolbarItem { ProgressView() }
                    }
                }
                .refreshable {
                    await syncStatus.run(statusText: "Locations") {
                        await viewModel.refresh(instances: instances, in: modelContext)
                        return viewModel.errorMessage == nil
                    }
                }
                .onChange(of: viewModel.isUnauthorized) { _, isUnauthorized in
                    if isUnauthorized { onUnauthorized() }
                }
            }
        }
        .navigationTitle("Locations")
    }

    @ViewBuilder
    private func locationRows(_ locations: [CachedLocation]) -> some View {
        if locations.isEmpty && !viewModel.isLoading {
            emptyState
        } else {
            ForEach(locations) { location in
                LocationRow(location: location, instance: instance(for: location))
            }
        }
    }

    @ViewBuilder
    private func mergedLocationRows(_ items: [CachedLocation.MergedItem]) -> some View {
        if items.isEmpty && !viewModel.isLoading {
            emptyState
        } else {
            let showsInstances = instances.count > 1
            ForEach(items) { item in
                LocationRow(
                    location: item.location, instance: instance(for: item.location),
                    instanceNames: showsInstances ? item.instanceNames : [])
                    .instanceEdge(named: showsInstances ? InstanceEdge.name(for: item.instanceNames) : nil, colors: instanceColors)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Locations",
            systemImage: "mappin.and.ellipse",
            description: Text("There are no locations yet.")
        )
    }
}

private struct LocationRow: View {
    let location: CachedLocation
    /// The instance to resolve a credential against for this location's own live
    /// refresh — `nil` only if the location's `instanceID` somehow doesn't match any
    /// currently active instance (e.g. a race with deactivation), in which case the
    /// row still navigates, just without a working pull-to-refresh on the detail screen.
    var instance: Instance?
    /// The instances this location belongs to (merged mode with several instances); badges, one each.
    var instanceNames: [String] = []

    var body: some View {
        NavigationLink {
            LocationDetailView(location: location, instance: instance)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(location.name)
                        .font(.headline)
                    if !instanceNames.isEmpty {
                        Spacer()
                        ForEach(instanceNames, id: \.self) { name in
                            InstanceBadge(name: name)
                        }
                    }
                }
                Text(location.locationDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.vertical, 2)
        }
    }
}
