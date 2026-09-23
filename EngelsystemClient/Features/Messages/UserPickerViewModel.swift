import Foundation
import EngelsystemClientKit

/// Backs the "start a new conversation" picker (`UserPickerView`) — lists every user
/// on the chosen instance via `GET /users`.
@Observable
@MainActor
final class UserPickerViewModel {
    var users: [Reference] = []
    var isLoading = false
    var errorMessage: String?

    private let credentialResolver: InstanceCredentialResolver
    private let apiClient: APIClient

    init(credentialResolver: InstanceCredentialResolver = InstanceCredentialResolver(), apiClient: APIClient = .shared) {
        self.credentialResolver = credentialResolver
        self.apiClient = apiClient
    }

    func load(instance: Instance) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let credential = try credentialResolver.credential(for: instance)
            users = try await apiClient.fetchUsers(credential).sorted {
                ($0.name ?? "") < ($1.name ?? "")
            }
            DebugLog.log("[UserPickerViewModel] loaded \(users.count) user(s) for '\(instance.name)'")
        } catch {
            if error is CancellationError { return }
            DebugLog.log("[UserPickerViewModel] load failed: \(error)", level: .error)
            errorMessage = SyncErrorMapper.message(for: error)
        }
    }
}
