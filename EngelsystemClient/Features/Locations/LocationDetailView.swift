import SwiftUI
import SwiftData
import EngelsystemClientKit

/// Shows one location's full detail — reached from `LocationsView` and from a shift's
/// location link (`ShiftsView`). Pull-to-refresh live-refreshes just this location via
/// `GET /locations/{id}` (2026-09-23) when `instance` is known; otherwise (a race with
/// the owning instance being deactivated) the screen still shows whatever's cached,
/// just without a working refresh.
struct LocationDetailView: View {
    let location: CachedLocation
    let instance: Instance?

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = LocationDetailViewModel()
    @AppStorage(MapLinkMode.userDefaultsKey) private var mapLinkModeRaw: String = MapLinkMode.embedded.rawValue

    @State private var mapDataChecked = false
    @AppStorage(MapWebsiteDataRetention.userDefaultsKey) private var autoDeleteDays: Int = MapWebsiteDataRetention.defaultDays

    private var mapLinkMode: MapLinkMode { MapLinkMode.stored(raw: mapLinkModeRaw) }

    /// The embeddable map address when the embedded map is on and this location has one.
    private var embeddedMapURL: URL? {
        mapLinkMode == .embedded ? MapLinkMode.embeddableURL(location.mapUrl) : nil
    }

    var body: some View {
        Group {
            if let embeddedMapURL {
                embeddedLayout(mapURL: embeddedMapURL)
            } else {
                listLayout
            }
        }
        .task {
            await MapWebsiteData.deleteIfDue(days: autoDeleteDays)
            mapDataChecked = true
        }
        .navigationTitle(location.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if viewModel.isLoading {
                ToolbarItem { ProgressView() }
            }
        }
        .refreshable {
            guard let instance else { return }
            await viewModel.refresh(location: location, instance: instance, in: modelContext)
        }
    }

    /// Embedded map: the text information takes exactly the height it needs at the top and the
    /// map takes all the remaining space down to the bottom edge. The map only starts loading
    /// once the automatic cleanup of its website data (`MapWebsiteData.deleteIfDue`) has run.
    private func embeddedLayout(mapURL: URL) -> some View {
        VStack(spacing: 0) {
            embeddedInfo
            Divider()
            if mapDataChecked {
                EmbeddedMapView(url: mapURL, autoDeleteDays: autoDeleteDays)
                    .frame(maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }
        }
    }

    private var embeddedInfo: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let errorMessage = viewModel.errorMessage {
                ErrorBanner(message: errorMessage)
            }
            Text(location.locationDescription)
            if let contactDect = location.contactDect {
                VStack(alignment: .leading, spacing: 2) {
                    LabeledContent("DECT", value: contactDect)
                    Text("Internal short number — reachable from any DECT phone on site.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if let url = URL(string: location.mapUrl ?? "") {
                Link(destination: url) {
                    Label("Open Map in Browser", systemImage: "safari")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var listLayout: some View {
        Form {
            if let errorMessage = viewModel.errorMessage {
                Section {
                    ErrorBanner(message: errorMessage)
                }
                .listRowInsets(EdgeInsets())
            }

            Section {
                Text(location.locationDescription)
            }

            if let contactDect = location.contactDect {
                Section {
                    LabeledContent("DECT", value: contactDect)
                } footer: {
                    Text("Internal short number — reachable from any DECT phone on site.")
                }
            }

            if let mapUrl = location.mapUrl, let url = URL(string: mapUrl) {
                Section {
                    Link(destination: url) {
                        Label("Show Map", systemImage: "map")
                    }
                }
            }
        }
    }
}
