import SwiftUI
import SwiftData
import EngelsystemClientKit

struct NewsView: View {
    let instance: Instance
    var onUnauthorized: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = NewsViewModel()
    @Query private var newsItems: [CachedNews]

    init(instance: Instance, onUnauthorized: @escaping () -> Void = {}) {
        self.instance = instance
        self.onUnauthorized = onUnauthorized
        let instanceID = instance.id
        _newsItems = Query(filter: #Predicate<CachedNews> { $0.instanceID == instanceID })
    }

    private var sortedNews: [CachedNews] { CachedNews.sortedByRecency(newsItems) }

    var body: some View {
        List {
            if let errorMessage = viewModel.errorMessage {
                Section {
                    ErrorBanner(message: errorMessage)
                }
                .listRowInsets(EdgeInsets())
            }

            if newsItems.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "No News",
                    systemImage: "newspaper",
                    description: Text("There's no news yet.")
                )
            } else {
                ForEach(sortedNews) { item in
                    NewsRow(item: item)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("News")
        .toolbar {
            if viewModel.isLoading {
                ToolbarItem { ProgressView() }
            }
        }
        .refreshable { await viewModel.refresh(instance: instance, in: modelContext) }
        .task { await viewModel.refresh(instance: instance, in: modelContext) }
        .onChange(of: viewModel.isUnauthorized) { _, isUnauthorized in
            if isUnauthorized { onUnauthorized() }
        }
    }
}

private struct NewsRow: View {
    let item: CachedNews

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
