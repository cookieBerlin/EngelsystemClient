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
    @State private var meetingFilter: NewsMeetingFilter = .all
    @AppStorage(MultiInstanceDisplayMode.userDefaultsKey)
    private var displayModeRaw: String = MultiInstanceDisplayMode.merged.rawValue
    @Query private var allNewsItems: [CachedNews]

    private var displayMode: MultiInstanceDisplayMode {
        guard instances.count > 1 else { return .merged }
        return MultiInstanceDisplayMode(rawValue: displayModeRaw) ?? .merged
    }

    private var instanceIDs: Set<UUID> { Set(instances.map(\.id)) }
    private var activeInstanceNewsItems: [CachedNews] { allNewsItems.filter { instanceIDs.contains($0.instanceID) } }
    private var newsItems: [CachedNews] { activeInstanceNewsItems.filter(meetingFilter.matches) }

    private var switcherInstance: Instance? {
        instances.first(where: { $0.id == selectedInstanceID }) ?? instances.first
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
                        // see CachedNews.mergedAcrossServers. Each surviving item keeps
                        // the name of *every* contributing instance, not just one, so
                        // the badge row reflects all of them.
                        let merged = CachedNews.mergedAcrossServers(CachedNews.sortedByRecency(newsItems), instances: instances)
                        mergedNewsRows(merged)
                    case .switcher:
                        InstancePicker(instances: instances, selection: $selectedInstanceID)
                            .listRowSeparator(.hidden)
                        let filtered = newsItems.filter { $0.instanceID == switcherInstance?.id }
                        newsRows(CachedNews.sortedByRecency(filtered))
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
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Picker("Filter", selection: $meetingFilter) {
                                ForEach(NewsMeetingFilter.allCases) { filter in
                                    Text(filter.title).tag(filter)
                                }
                            }
                        } label: {
                            Label(
                                "Filter",
                                systemImage: meetingFilter == .all
                                    ? "line.3.horizontal.decrease.circle"
                                    : "line.3.horizontal.decrease.circle.fill"
                            )
                        }
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
    private func newsRows(_ items: [CachedNews]) -> some View {
        if items.isEmpty && !viewModel.isLoading {
            emptyState
        } else {
            ForEach(items) { item in
                NewsRow(item: item)
            }
        }
    }

    @ViewBuilder
    private func mergedNewsRows(_ items: [CachedNews.MergedItem]) -> some View {
        if items.isEmpty && !viewModel.isLoading {
            emptyState
        } else {
            ForEach(items) { merged in
                NewsRow(item: merged.item, instanceNames: merged.instanceNames)
            }
        }
    }

    /// Distinguishes "there's genuinely no news" from "the filter hid everything" —
    /// otherwise a `.meetingsOnly`/`.nonMeetingsOnly` filter with zero matches would
    /// misleadingly look identical to an instance with no news at all.
    @ViewBuilder
    private var emptyState: some View {
        if meetingFilter != .all && !activeInstanceNewsItems.isEmpty {
            ContentUnavailableView(
                "No Matching News",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("No news matches the current filter.")
            )
        } else {
            ContentUnavailableView(
                "No News",
                systemImage: "newspaper",
                description: Text("There's no news yet.")
            )
        }
    }
}

private struct NewsRow: View {
    let item: CachedNews
    /// Every active instance this post actually appears on — usually one, but more
    /// than one when the same server is configured under multiple instances and this
    /// row is the merged, deduplicated representative for all of them (see
    /// `CachedNews.mergedAcrossServers`). Empty in `.switcher`/`.sectioned`, where the
    /// surrounding context (picker/section header) already makes the instance clear.
    var instanceNames: [String] = []

    /// Collapsed by default whenever there's a `[more]` split — matches the website's
    /// "read more" behavior (2026-09-22, user-reported: the app previously always
    /// showed the full text regardless of the tag).
    @State private var isExpanded = false

    private var textParts: CachedNews.TextParts { CachedNews.textParts(from: item.text) }

    private func attributed(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
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
                if !instanceNames.isEmpty {
                    Spacer()
                    ForEach(instanceNames, id: \.self) { name in
                        InstanceBadge(name: name)
                    }
                }
            }
            Text(attributed(textParts.preview))
                .font(.body)
                .foregroundStyle(.secondary)
            if let rest = textParts.rest {
                if isExpanded {
                    // Set apart from the preview — an indented box, not just another
                    // paragraph — so it reads as "the expanded part", not as if it had
                    // been there all along (2026-09-22, user-requested).
                    Text(attributed(rest))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.leading, 12)
                }
                Button(isExpanded ? "Show Less" : "Read More") {
                    withAnimation { isExpanded.toggle() }
                }
                .font(.caption)
            }
            Text(item.createdAt, style: .date)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
