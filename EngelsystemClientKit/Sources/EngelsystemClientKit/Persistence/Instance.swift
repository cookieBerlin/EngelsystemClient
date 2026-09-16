import Foundation
import SwiftData

/// CloudKit-backed (see CLAUDE.md's Sync strategy) — lives in its own `ModelConfiguration`,
/// separate from the local-only `Cached*` models, so it can sync between the iOS and Watch
/// apps via the shared `iCloud.net.cuccato.engelsystem.de` container. This is why every
/// stored property below needs a default value (CloudKit's SwiftData integration requires
/// every attribute to be optional or have a default — its own record-construction path
/// doesn't go through this type's custom `init`) and why `id` no longer has `.unique`
/// (CloudKit doesn't support unique constraints at all). `Cached*` models keep their
/// `.unique` `uid` since they stay in the local-only configuration.
@Model
public final class Instance {
    public var id: UUID = UUID()
    public var name: String = ""
    public var baseURL: String = ""
    // Stores only the Keychain reference key, never the API key itself
    public var apiKeyKeychainRef: String = ""
    // Fallback for servers that 404 on the documented `self` path parameter alias
    // (confirmed to happen on at least one real, older Engelsystem deployment) —
    // nil means "use `self`", the default and normal case. See `userReference` below.
    public var userID: Int?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    // No relationships to the Cached* models: they live in a separate, local-only
    // ModelConfiguration (see the app targets' ModelContainer setup), and SwiftData
    // relationships can't cross configurations. Deleting an Instance's cached data is
    // therefore done manually (see SettingsView/WatchSettingsView's delete(_:)) instead
    // of via an automatic cascade-delete relationship like before.

    public init(
        id: UUID = UUID(),
        name: String,
        baseURL: String,
        apiKeyKeychainRef: String,
        userID: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKeyKeychainRef = apiKeyKeychainRef
        self.userID = userID
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

public extension Instance {
    func touch() { updatedAt = Date() }

    static func normalizedBaseURL(_ baseURL: String) -> String {
        baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static func apiBasePath(for baseURL: String) -> String {
        "\(normalizedBaseURL(baseURL))/api/v0-beta"
    }

    var normalizedBaseURL: String { Instance.normalizedBaseURL(baseURL) }

    var apiBasePath: String { Instance.apiBasePath(for: baseURL) }

    /// Sentinel base URL recognized by `APIClient` — an instance using this URL never
    /// makes real network requests; `APIClient` returns static mock data instead
    /// (see `DemoData`). Lets the app be tried out without a real server or API key.
    static let demoBaseURL = "demo://engelsystem.local"

    var isDemo: Bool { normalizedBaseURL == Instance.demoBaseURL }

    /// How to address "myself" in `/users/{id}/...` API calls — `self` unless a
    /// numeric fallback `userID` has been set for a server that doesn't support that
    /// alias (see `userID` above).
    var userReference: UserReference {
        userID.map { .id($0) } ?? .me
    }
}
