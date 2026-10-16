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
    // Whether this instance's data (Shifts/News/Profile, the Watch's next shift) is
    // currently included. Replaces the old single "active instance" concept (2026-09-17
    // multi-active-instance redesign, CLAUDE.md) — any number of instances can be active
    // simultaneously. Defaults to true so a newly created instance shows up immediately
    // without a separate activation step.
    public var isActive: Bool = true
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    // CloudKit-synced "something changed" signal (2026-09-23, user-requested "keep the
    // Watch fresh" feature): bumped by `ShiftSyncService`/`AppSyncCoordinator` whenever a
    // sync detects a genuine shift change. Deliberately a plain timestamp on the same
    // already-CloudKit-backed `Instance` model, rather than a new model — reuses the
    // proven CloudKit-sync/`refreshesOnRemoteCloudKitChange` machinery instead of adding a
    // parallel one. `.distantPast` default so a freshly created/synced `Instance` never
    // looks "just changed" to a device that hasn't seen this field before.
    public var shiftsChangedAt: Date = Date.distantPast
    // Whether this instance's server exposes the `/messages` API (2026-09-23) — not
    // every Engelsystem deployment does yet, so the Messages sidebar entry/screens must
    // stay hidden entirely rather than show and then fail. Defaults pessimistically to
    // COMPAT(#1720): `false`: a server that doesn't
    // support Messages at all should never briefly show the UI before a probe corrects
    // it. Kept up to date by `AppSyncCoordinator`'s lightweight per-sync capability
    // check (`APIClient.messagesSupported(_:)`) — no dedicated Setup/Edit-time probe,
    // to keep that flow simple; the periodic re-check is enough to pick up a server that
    // gains support later.
    public var messagesSupported: Bool = false
    // The color the user picked for this instance (`InstancePalette` raw value), CloudKit-synced so every
    // device shows the same. nil is "Auto": `InstancePalette.assignments(for:)` spreads the colors evenly.
    // A new optional attribute is a lightweight change for the CloudKit schema; older app versions ignore it.
    public var colorKey: String?

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
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKeyKeychainRef = apiKeyKeychainRef
        self.isActive = isActive
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
    static let demoBaseURL = DemoScenario.main.baseURL

    /// Any `demo://` address is a demo instance; the host picks the data (`DemoScenario`).
    var isDemo: Bool { normalizedBaseURL.hasPrefix(DemoScenario.scheme) }

    /// A demo instance whose server offers only News (an unknown `demo://` address).
    var isNewsOnlyDemo: Bool { DemoScenario.isNewsOnly(address: normalizedBaseURL) }
}
