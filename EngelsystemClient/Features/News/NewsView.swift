import SwiftUI
import SwiftData
import EngelsystemClientKit

/// 2026-09-17 multi-active-instance redesign (CLAUDE.md): `instances` is every
/// currently active instance, aggregated per `MultiInstanceDisplayMode` — see
/// `ShiftsView` for the shared pattern.
struct NewsView: View {
    let instances: [Instance]
    var onUnauthorized: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = NewsViewModel()
    @State private var selectedInstanceID: UUID?
    @AppStorage(MultiInstanceDisplayMode.userDefaultsKey)
    private var displayModeRaw: String = MultiInstanceDisplayMode.merged.rawValue
    @Query private var allNewsItems: [CachedNews]

    private var displayMode: MultiInstanceDisplayMode {
        guard instances.count > 1 else { return .merged }
        return MultiInstanceDisplayMode(rawValue: displayModeRaw) ?? .merged
    }

    private var instanceIDs: Set<UUID> { Set(instances.map(\.id)) }
    private var newsItems: [CachedNews] { allNewsItems.filter { instanceIDs.contains($0.instanceID) } }

    private var switcherInstance: Instance? {
        instances.first(where: { $0.id == selectedInstanceID }) ?? instances.first
    }

    private func instanceName(for item: CachedNews) -> String? {
        instances.first(where: { $0.id == item.instanceID })?.name
    }

    var body: some View {
        Group {
            if instances.isEmpty {
                ContentUnavailableView(
                    "No Active Instance",
                    systemImage: "newspaper",
                    description: Text("Activate an instance in Settings to see its news.")
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
                        // Two active instances pointing at the same actual server
                        // (e.g. different user accounts for one event) would otherwise
                        // each contribute their own cached copy of the same news post —
                        // see CachedNews.deduplicatedByServer.
                        let merged = CachedNews.deduplicatedByServer(CachedNews.sortedByRecency(newsItems), instances: instances)
                        newsRows(merged, labeled: true)
                    case .switcher:
                        InstancePicker(instances: instances, selection: $selectedInstanceID)
                            .listRowSeparator(.hidden)
                        let filtered = newsItems.filter { $0.instanceID == switcherInstance?.id }
                        newsRows(CachedNews.sortedByRecency(filtered), labeled: false)
                    case .sectioned:
                        ForEach(instances) { instance in
                            let instanceNews = CachedNews.sortedByRecency(newsItems.filter { $0.instanceID == instance.id })
                            if !instanceNews.isEmpty {
                                Section(instance.name) {
                                    ForEach(instanceNews) { item in
                                        NewsRow(item: item)
                                    }
                                }
                            }
                        }
                        if newsItems.isEmpty && !viewModel.isLoading {
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
                .refreshable { await viewModel.refresh(instances: instances, in: modelContext) }
                .task { await viewModel.refresh(instances: instances, in: modelContext) }
                .onChange(of: viewModel.isUnauthorized) { _, isUnauthorized in
                    if isUnauthorized { onUnauthorized() }
                }
            }
        }
        .navigationTitle("News")
    }

    @ViewBuilder
    private func newsRows(_ items: [CachedNews], labeled: Bool) -> some View {
        if items.isEmpty && !viewModel.isLoading {
            emptyState
        } else {
            ForEach(items) { item in
                NewsRow(item: item, instanceName: labeled ? instanceName(for: item) : nil)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No News",
            systemImage: "newspaper",
            description: Text("There's no news yet.")
        )
    }
}

private struct NewsRow: View {
    let item: CachedNews
    var instanceName: String?

    private var attributedText: AttributedString {
        (try? AttributedString(markdown: item.text)) ?? AttributedString(item.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(.orange)
                }
                Text(item.title)
                    .font(.headline)
                if item.isMeeting {
                    Text("Meeting")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.blue.opacity(0.2)))
                }
                if let instanceName {
                    Spacer()
                    InstanceBadge(name: instanceName)
                }
            }
            Text(attributedText)
                .font(.body)
                .foregroundStyle(.secondary)
            Text(item.createdAt, style: .date)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
