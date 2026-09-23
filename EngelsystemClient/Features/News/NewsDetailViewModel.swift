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

    private let credentialResolver: InstanceCredentialResolver
    private let apiClient: APIClient

    init(credentialResolver: InstanceCredentialResolver = InstanceCredentialResolver(), apiClient: APIClient = .shared) {
        self.credentialResolver = credentialResolver
        self.apiClient = apiClient
    }

    func refresh(newsServerID: Int, instance: Instance) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let credential = try credentialResolver.credential(for: instance)
            let detail = try await apiClient.fetchNewsDetail(id: newsServerID, credential)
            comments = detail.comments.sorted { $0.createdAt < $1.createdAt }
            DebugLog.log("[NewsDetailViewModel] loaded \(comments.count) comment(s) for news \(newsServerID)")
        } catch {
            // Same guard every other sync entry point in this app applies — a
            // SwiftUI `.task` cancelled because the view disappeared isn't a real
            // failure and shouldn't show an error banner.
            if error is CancellationError { return }
            DebugLog.log("[NewsDetailViewModel] refresh failed: \(error)", level: .error)
            errorMessage = SyncErrorMapper.message(for: error)
        }
    }
}
