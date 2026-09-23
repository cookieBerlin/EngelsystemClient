import SwiftUI
import EngelsystemClientKit

/// 2026-09-23, Messages feature: lets the user send/receive private messages.
/// `instances` must already be filtered down to active instances whose server
/// reports `messagesSupported` (see `MainView.Section.visibleSidebarCases`) — this
/// screen has no fallback UI for an unsupported instance, since it's never supposed
/// to be reachable with one in the first place.
///
/// Live-only (no `Cached*`/`@Query`, unlike Shifts/News/Profile/Locations) — see
/// `MessagesViewModel`'s doc comment for why. `MultiInstanceDisplayMode` still
/// applies, matching every other multi-instance screen.
struct MessagesView: View {
    let instances: [Instance]
    /// Shared with `MainView` — see `ShiftsView`'s matching property for why.
    let syncStatus: MainSyncStatus
    var onUnauthorized: () -> Void = {}

    @State private var viewModel = MessagesViewModel()
    @State private var selectedInstanceID: UUID?
    @State private var isShowingNewConversation = false
    @State private var pendingConversation: PendingConversation?
    @AppStorage(MultiInstanceDisplayMode.userDefaultsKey)
    private var displayModeRaw: String = MultiInstanceDisplayMode.merged.rawValue

    private var displayMode: MultiInstanceDisplayMode {
        guard instances.count > 1 else { return .merged }
        return MultiInstanceDisplayMode(rawValue: displayModeRaw) ?? .merged
    }

    private var switcherInstance: Instance? {
        instances.first(where: { $0.id == selectedInstanceID }) ?? instances.first
    }

    private func conversations(for instance: Instance) -> [Conversation] {
        (viewModel.conversationsByInstanceID[instance.id] ?? [])
            .sorted { $0.latestMessage.createdAt > $1.latestMessage.createdAt }
    }

    private var allConversations: [(instance: Instance, conversation: Conversation)] {
        instances.flatMap { instance in
            conversations(for: instance).map { (instance: instance, conversation: $0) }
        }.sorted { $0.conversation.latestMessage.createdAt > $1.conversation.latestMessage.createdAt }
    }

    var body: some View {
        Group {
            if instances.isEmpty {
                ContentUnavailableView(
                    "No Active Instance",
                    systemImage: "message",
                    description: Text("Activate an instance that supports messaging in Settings.")
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
                        conversationRows(allConversations)
                    case .switcher:
                        InstancePicker(instances: instances, selection: $selectedInstanceID)
                            .listRowSeparator(.hidden)
                        if let switcherInstance {
                            let rows = conversations(for: switcherInstance).map { (instance: switcherInstance, conversation: $0) }
                            conversationRows(rows)
                        }
                    case .sectioned:
                        ForEach(instances) { instance in
                            let rows = conversations(for: instance)
                            if !rows.isEmpty {
                                Section(instance.name) {
                                    ForEach(rows, id: \.otherUser.id) { conversation in
                                        ConversationRow(instance: instance, conversation: conversation, showsInstanceBadge: false)
                                    }
                                }
                            }
                        }
                        if allConversations.isEmpty && !viewModel.isLoading {
                            emptyState
                        }
                    }
                }
                .listStyle(.plain)
                .toolbar {
                    if viewModel.isLoading {
                        ToolbarItem { ProgressView() }
                    }
                    ToolbarItem {
                        Button {
                            isShowingNewConversation = true
                        } label: {
                            Label("New Message", systemImage: "square.and.pencil")
                        }
                    }
                }
                .refreshable {
                    await syncStatus.run(statusText: "Messages") {
                        await viewModel.refresh(instances: instances)
                        return viewModel.errorMessage == nil
                    }
                }
                .task {
                    await viewModel.refresh(instances: instances)
                }
                .onChange(of: viewModel.isUnauthorized) { _, isUnauthorized in
                    if isUnauthorized { onUnauthorized() }
                }
                .sheet(isPresented: $isShowingNewConversation) {
                    NewConversationView(instances: instances) { instance, user in
                        isShowingNewConversation = false
                        pendingConversation = PendingConversation(instance: instance, otherUser: user)
                    }
                }
                .navigationDestination(item: $pendingConversation) { pending in
                    ConversationDetailView(instance: pending.instance, otherUser: pending.otherUser)
                }
            }
        }
        .navigationTitle("Messages")
    }

    @ViewBuilder
    private func conversationRows(_ rows: [(instance: Instance, conversation: Conversation)]) -> some View {
        if rows.isEmpty && !viewModel.isLoading {
            emptyState
        } else {
            ForEach(rows, id: \.conversation.otherUser.id) { row in
                ConversationRow(instance: row.instance, conversation: row.conversation, showsInstanceBadge: instances.count > 1)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Conversations",
            systemImage: "message",
            description: Text("Start a new conversation using the button above.")
        )
    }
}

/// Identifies which conversation to navigate into once `NewConversationView` finishes
/// — a plain struct rather than navigating directly from inside the sheet, since the
/// sheet needs to dismiss first (matching the standard "dismiss, then push" pattern for
/// starting a new item from a modal picker).
private struct PendingConversation: Identifiable, Hashable {
    let instance: Instance
    let otherUser: Reference

    var id: String { "\(instance.id)-\(otherUser.id)" }

    static func == (lhs: PendingConversation, rhs: PendingConversation) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

private struct ConversationRow: View {
    let instance: Instance
    let conversation: Conversation
    let showsInstanceBadge: Bool

    var body: some View {
        NavigationLink {
            ConversationDetailView(instance: instance, otherUser: conversation.otherUser)
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(conversation.otherUser.name ?? "User \(conversation.otherUser.id)")
                            .font(.headline)
                        if showsInstanceBadge {
                            InstanceBadge(name: instance.name)
                        }
                    }
                    Text(conversation.latestMessage.text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if conversation.unreadMessages > 0 {
                    Text("\(conversation.unreadMessages)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Circle().fill(Color.blue))
                }
            }
            .padding(.vertical, 2)
        }
    }
}
