import Foundation

/// The rules of the instance form (adding an instance, and the editable instance page): when an API key is
/// needed, which key is used, whether something changed and whether the form can be saved.
public enum InstanceForm {
    /// What a demo address stores as its key: the demo ignores it, but the key store needs a value.
    public static let demoAPIKey = "demo"

    /// A `demo://` address needs no API key.
    public static func requiresAPIKey(address: String) -> Bool {
        !trimmed(address).hasPrefix(DemoScenario.scheme)
    }

    /// The key to test and store: the demo key for a demo address, otherwise what was typed.
    public static func effectiveAPIKey(address: String, typed: String) -> String {
        requiresAPIKey(address: address) ? trimmed(typed) : demoAPIKey
    }

    /// The text below the key field of a demo address.
    public static let demoKeyHint = "Not needed for demo addresses"

    /// Name and address must not be empty.
    public static func canSave(name: String, address: String) -> Bool {
        !trimmed(name).isEmpty && !trimmed(address).isEmpty
    }

    /// Whether the form differs from the saved instance. A typed key always counts as a change (a blank key
    /// field means "keep the saved key").
    public static func hasChanges(
        savedName: String, savedAddress: String, name: String, address: String, typedKey: String
    ) -> Bool {
        trimmed(name) != trimmed(savedName)
            || Instance.normalizedBaseURL(trimmed(address)) != Instance.normalizedBaseURL(trimmed(savedAddress))
            || !trimmed(typedKey).isEmpty
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces)
    }
}
