import Foundation
import Observation

/// Optional server features that not every Engelsystem deployment offers (yet): the app
/// hides what a server lacks instead of showing errors. `COMPAT(#1710)` (comments) and
/// `COMPAT(#1711)` (locations) — removed again by backlog R-03/R-04/R-05 once the pull
/// requests are merged. See ADR 0013.
public enum ServerFeature: String, CaseIterable, Sendable {
    /// News comments (`comments_count` in `/news`, `GET /news/{id}`) — PR #1710.
    case newsComments
    /// The locations list (`GET /locations`); without PR #1711 only the `api` group may read it.
    case locationsList
    /// A single location (`GET /locations/{id}`) — PR #1711.
    case locationDetail
}

/// Which optional features each instance's server supports, learned for free from the
/// normal syncs. **Device-local** (`UserDefaults`, not CloudKit): no schema change, and each
/// device learns it from its own syncs. Unknown means "available" — the UI only hides a
/// feature after a sync proved the server lacks it. `@Observable` so SwiftUI hides/shows
/// affected UI as soon as a sync records a change.
@MainActor
@Observable
public final class ServerCapabilities {
    public static let shared = ServerCapabilities()

    static let defaultsKey = "serverCapabilities"

    @ObservationIgnored private let defaults: UserDefaults
    private var values: [String: Bool]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.values = (defaults.dictionary(forKey: Self.defaultsKey) as? [String: Bool]) ?? [:]
    }

    private static func key(_ feature: ServerFeature, _ instanceID: UUID) -> String {
        instanceID.uuidString + "/" + feature.rawValue
    }

    /// `false` only once a sync showed that the server lacks `feature`.
    public func isAvailable(_ feature: ServerFeature, for instanceID: UUID) -> Bool {
        values[Self.key(feature, instanceID)] ?? true
    }

    /// Remembers the outcome of a probe/sync; `nil` ("could not tell", e.g. an empty news
    /// list) leaves the previous knowledge untouched.
    public func record(_ feature: ServerFeature, supported: Bool?, for instanceID: UUID) {
        guard let supported else { return }
        let key = Self.key(feature, instanceID)
        guard values[key] != supported else { return }
        values[key] = supported
        defaults.set(values, forKey: Self.defaultsKey)
    }

    /// Whether the feature is available on at least one of the given instances.
    public func isAvailable(_ feature: ServerFeature, forAnyOf instanceIDs: [UUID]) -> Bool {
        instanceIDs.contains { isAvailable(feature, for: $0) }
    }

    /// `COMPAT(#1710)`: a server supports news comments exactly when its `/news` items carry
    /// `comments_count`. An empty list says nothing (`nil`).
    public static func newsCommentsSupported(by items: [News]) -> Bool? {
        guard !items.isEmpty else { return nil }
        return items.contains { $0.commentsCount != nil }
    }
}
