import Foundation
import EngelsystemClientKit

/// 2026-09-23, Messages feature. Deliberately *not* backed by SwiftData/`XSyncService`
/// like Shifts/News/Locations — Messages is this app's first mutable, bidirectional
/// data, and a local cache would need to reconcile offline writes against a live
/// server; a live-only fetch (matching `NewsDetailViewModel`'s comments) sidesteps that
/// entirely for a first version. Callers are expected to pass only instances that are
/// both active and report `messagesSupported` — this view model has no opinion on
/// that filtering itself.
@Observable
@MainActor
final class MessagesViewModel {
    /// Keyed by `Instance.id` rather than a single flat array, so the view can render
    /// merged/switcher/sectioned per `MultiInstanceDisplayMode` the same way
    /// `LocationsView`/`ShiftsView` do over their own `@Query`-backed data.
    var conversationsByInstanceID: [UUID: [Conversation]] = [:]
    var isLoading = false
    var errorMessage: String?
    var isUnauthorized = false

    private let credentialResolver: InstanceCredentialResolver
    private let apiClient: APIClient
    private let capabilities: ServerCapabilities

    init(credentialResolver: InstanceCredentialResolver = InstanceCredentialResolver(), apiClient: APIClient = .shared,
         capabilities: ServerCapabilities? = nil) {
        self.credentialResolver = credentialResolver
        self.apiClient = apiClient
        self.capabilities = capabilities ?? .shared
    }

    /// Fetches every given instance's conversation list. A failure on one instance
    /// doesn't stop the others from refreshing, matching every other multi-instance
    /// sync in this app.
    func refresh(instances: [Instance]) async {
        errorMessage = nil
        isUnauthorized = false
        isLoading = true
        defer { isLoading = false }

        var lastError: Error?

        for instance in instances {
            do {
                let credential = try credentialResolver.credential(for: instance)
                let conversations = try await apiClient.fetchConversations(credential)
                conversationsByInstanceID[instance.id] = conversations
                DebugLog.log("[MessagesViewModel] loaded \(conversations.count) conversation(s) for '\(instance.name)'")
                capabilities.record(.messages, state: .available, evidence: .probe, for: instance.id)
            } catch {
                if error is CancellationError { continue }
                DebugLog.log("[MessagesViewModel] refresh failed for '\(instance.name)': \(error)", level: .error)
                // Not allowed / not offered (403/404): hidden silently, see the Features list (ADR 0015).
                if capabilities.record(.messages, afterError: error, for: instance.id) { continue }
                lastError = error
            }
        }

        if let lastError {
            errorMessage = SyncErrorMapper.message(for: lastError)
            isUnauthorized = SyncErrorMapper.isUnauthorized(lastError)
        }
    }
}
