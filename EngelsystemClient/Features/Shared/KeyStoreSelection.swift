import Foundation
import EngelsystemClientKit

/// Which Keychain store a freshly typed API key goes to first: the iCloud-synced one when
/// iCloud is available, the device-local one otherwise — and the other one as the
/// secondary store that a key is mirrored into. Pure, so both branches are unit-testable
/// without depending on the machine's iCloud state.
enum KeyStoreSelection {
    static func stores(iCloudAvailable: Bool) -> (primary: APIKeyStore, secondary: APIKeyStore) {
        iCloudAvailable
            ? (KeychainSyncStore(), LocalKeychainStore())
            : (LocalKeychainStore(), KeychainSyncStore())
    }

    static func currentStores() -> (primary: APIKeyStore, secondary: APIKeyStore) {
        stores(iCloudAvailable: ICloudAvailability.isAvailable)
    }
}
