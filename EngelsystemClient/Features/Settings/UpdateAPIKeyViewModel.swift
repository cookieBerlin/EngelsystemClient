import Foundation
import EngelsystemClientKit

@Observable
@MainActor
final class UpdateAPIKeyViewModel {
    var apiKey: String = ""
    var isTesting = false
    var errorMessage: String?

    private let setupService: InstanceSetupService

    init(setupService: InstanceSetupService = InstanceSetupService()) {
        self.setupService = setupService
    }

    var canSubmit: Bool {
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty && !isTesting
    }

    /// Tests the new key against the instance's existing server and, on success,
    /// overwrites the stored key in place (see `InstanceSetupService.updateAPIKey`).
    /// Which store (iCloud vs. local) the key originally landed in isn't tracked on
    /// `Instance`, so after the network test succeeds the new key is mirrored into
    /// both — otherwise a stale value could linger in whichever store
    /// `InstanceCredentialResolver` happens to check first.
    func update(instance: Instance) async -> Bool {
        errorMessage = nil
        isTesting = true
        defer { isTesting = false }

        let primaryStore: APIKeyStore = ICloudAvailability.isAvailable ? KeychainSyncStore() : LocalKeychainStore()
        let secondaryStore: APIKeyStore = ICloudAvailability.isAvailable ? LocalKeychainStore() : KeychainSyncStore()
        do {
            try await setupService.updateAPIKey(for: instance, apiKey: apiKey, store: primaryStore)
            try? secondaryStore.save(apiKey: apiKey, for: instance.apiKeyKeychainRef)
            return true
        } catch {
            errorMessage = SyncErrorMapper.message(for: error)
            return false
        }
    }
}
