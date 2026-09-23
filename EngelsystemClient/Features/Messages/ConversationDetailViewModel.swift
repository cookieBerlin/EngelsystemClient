import Foundation
import EngelsystemClientKit

/// Drives a single conversation's message thread (`ConversationDetailView`) — send,
/// delete own messages, and auto-mark-read on open. Live-only, same reasoning as
/// `MessagesViewModel`.
@Observable
@MainActor
final class ConversationDetailViewModel {
    var messages: [Message] = []
    var isLoading = false
    var isSending = false
    var errorMessage: String?

    private let credentialResolver: InstanceCredentialResolver
    private let apiClient: APIClient

    init(credentialResolver: InstanceCredentialResolver = InstanceCredentialResolver(), apiClient: APIClient = .shared) {
        self.credentialResolver = credentialResolver
        self.apiClient = apiClient
    }

    /// Loads the full thread with `otherUserID`, then marks every unread *incoming*
    /// message read. "Incoming" is determined structurally — `sender.id == otherUserID`
    /// — rather than by comparing against the signed-in user's own id: this live-only
    /// feature has no other reason to resolve that id, and the sender/receiver pair
    /// already fully describes direction for a two-party conversation.
    func load(otherUserID: Int, instance: Instance) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let credential = try credentialResolver.credential(for: instance)
            let thread = try await apiClient.fetchConversation(otherUserID: otherUserID, credential)
            messages = thread.sorted { $0.createdAt < $1.createdAt }
            DebugLog.log("[ConversationDetailViewModel] loaded \(messages.count) message(s) with user \(otherUserID)")
            await markIncomingMessagesRead(otherUserID: otherUserID, credential: credential)
        } catch {
            if error is CancellationError { return }
            DebugLog.log("[ConversationDetailViewModel] load failed: \(error)", level: .error)
            errorMessage = SyncErrorMapper.message(for: error)
        }
    }

    private func markIncomingMessagesRead(otherUserID: Int, credential: EventCredential) async {
        let unreadIncoming = messages.filter { !$0.read && $0.sender.id == otherUserID }
        for message in unreadIncoming {
            do {
                let updated = try await apiClient.setMessageRead(id: message.id, read: true, credential)
                if let index = messages.firstIndex(where: { $0.id == updated.id }) {
                    messages[index] = updated
                }
            } catch {
                // Not surfaced as a screen-level error — the thread itself loaded fine,
                // and a stray unread flag isn't worth interrupting the user over.
                DebugLog.log("[ConversationDetailViewModel] failed to mark message \(message.id) read: \(error)", level: .error)
            }
        }
    }

    @discardableResult
    func send(text: String, otherUserID: Int, instance: Instance) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        isSending = true
        defer { isSending = false }

        do {
            let credential = try credentialResolver.credential(for: instance)
            let sent = try await apiClient.sendMessage(to: otherUserID, text: trimmed, credential)
            messages.append(sent)
            return true
        } catch {
            DebugLog.log("[ConversationDetailViewModel] send failed: \(error)", level: .error)
            errorMessage = SyncErrorMapper.message(for: error)
            return false
        }
    }

    /// Deletes a message the signed-in user sent. Only meaningful for messages where
    /// `sender.id != otherUserID` (i.e. the signed-in user's own) — the server rejects
    /// deleting the other party's message with `403`; the view only ever offers this
    /// action on the user's own rows in the first place, so that's enforced by the UI,
    /// not re-checked here.
    func delete(_ message: Message, instance: Instance) async {
        do {
            let credential = try credentialResolver.credential(for: instance)
            try await apiClient.deleteMessage(id: message.id, credential)
            messages.removeAll { $0.id == message.id }
        } catch {
            DebugLog.log("[ConversationDetailViewModel] delete failed: \(error)", level: .error)
            errorMessage = SyncErrorMapper.message(for: error)
        }
    }
}
