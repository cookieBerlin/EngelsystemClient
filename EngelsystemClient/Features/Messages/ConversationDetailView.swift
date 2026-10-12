import SwiftUI
import EngelsystemClientKit

/// One conversation's message thread — compose/send, delete own messages, and
/// auto-mark-read on open (see `ConversationDetailViewModel`). Live-only, refetched
/// every time this screen opens.
struct ConversationDetailView: View {
    let instance: Instance
    let otherUser: Reference

    @State private var viewModel = ConversationDetailViewModel()
    @State private var draftText = ""

    var body: some View {
        VStack(spacing: 0) {
            if let errorMessage = viewModel.errorMessage {
                ErrorBanner(message: errorMessage)
            }

            ScrollViewReader { proxy in
                List {
                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message, isMine: message.sender.id != otherUser.id)
                            .id(message.id)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing) {
                                if message.sender.id != otherUser.id {
                                    Button("Delete", role: .destructive) {
                                        Task { await viewModel.delete(message, instance: instance) }
                                    }
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .onChange(of: viewModel.messages.count) { _, _ in
                    guard let lastID = viewModel.messages.last?.id else { return }
                    withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
                }
            }

            Divider()

            HStack {
                TextField("Message", text: $draftText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .accessibilityLabel("Send")
                .disabled(!ConversationDetailViewModel.canSend(draft: draftText, isSending: viewModel.isSending))
            }
            .padding()
        }
        .navigationTitle(otherUser.name ?? "User \(otherUser.id)")
        .task { await viewModel.load(otherUserID: otherUser.id, instance: instance) }
    }

    private func send() {
        let text = draftText
        draftText = ""
        Task {
            draftText = await viewModel.sendDraft(text, otherUserID: otherUser.id, instance: instance)
        }
    }
}

private struct MessageBubble: View {
    let message: Message
    let isMine: Bool

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 40) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
                Text(message.text)
                    .padding(10)
                    .background(isMine ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Text(message.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !isMine { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
    }
}
