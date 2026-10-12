import Foundation
import EngelsystemClientKit

/// Fetches a single news post's comments (`GET /news/{id}`, added 2026-09-22).
/// Deliberately *not* cached in SwiftData like the main News list — comments are only
/// ever needed while this one detail screen is open, so a live fetch each time it
/// appears is simpler than adding a new persisted model/sync cycle for it.
@Observable
@MainActor
final class NewsDetailViewModel {
    var comments: [NewsComment] = []
    var isLoading = false
    var errorMessage: String?
    /// COMPAT(#1710): set when the server has no `GET /news/{id}` (404/403) — the comments
    /// section is then hidden instead of showing an error.
    var commentsUnavailable = false

    private let credentialResolver: InstanceCredentialResolver
    private let apiClient: APIClient
    private let capabilities: ServerCapabilities

    init(
        credentialResolver: InstanceCredentialResolver = InstanceCredentialResolver(),
        apiClient: APIClient = .shared,
        capabilities: ServerCapabilities = .shared
    ) {
        self.credentialResolver = credentialResolver
        self.apiClient = apiClient
        self.capabilities = capabilities
    }

    /// COMPAT(#1710): whether a news row offers its "N Comments" link — it needs comments to
    /// exist and the instance's server to support them.
    static func showsCommentsLink(commentsCount: Int, instanceID: UUID, capabilities: ServerCapabilities = .shared) -> Bool {
        commentsCount > 0 && capabilities.isAvailable(.newsComments, for: instanceID)
    }

    func refresh(newsServerID: Int, instance: Instance) async {
        errorMessage = nil
        commentsUnavailable = false
        isLoading = true
        defer { isLoading = false }

        do {
            let credential = try credentialResolver.credential(for: instance)
            let detail = try await apiClient.fetchNewsDetail(id: newsServerID, credential)
            comments = detail.comments.sorted { $0.createdAt < $1.createdAt }
            capabilities.record(.newsComments, supported: true, for: instance.id)
            DebugLog.log("[NewsDetailViewModel] loaded \(comments.count) comment(s) for news \(newsServerID)")
        } catch {
            // Same guard every other sync entry point in this app applies — a
            // SwiftUI `.task` cancelled because the view disappeared isn't a real
            // failure and shouldn't show an error banner.
            if error is CancellationError { return }
            if let apiError = error as? APIError, [APIError.notFound, .forbidden].contains(apiError) {
                // COMPAT(#1710): a server without the endpoint — hide comments for it.
                DebugLog.log("[NewsDetailViewModel] server has no news comments (\(apiError)) — hiding the feature", level: .warning)
                capabilities.record(.newsComments, supported: false, for: instance.id)
                commentsUnavailable = true
                comments = []
                return
            }
            DebugLog.log("[NewsDetailViewModel] refresh failed: \(error)", level: .error)
            errorMessage = SyncErrorMapper.message(for: error)
        }
    }
}
