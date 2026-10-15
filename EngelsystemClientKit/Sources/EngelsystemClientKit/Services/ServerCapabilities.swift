import Foundation
import Observation

/// Functions of the app that depend on what a server offers and what the account may use. The app
/// hides what is missing instead of showing errors, and the instance's "Features" list explains
/// it (ADR 0015). Fallbacks for older servers are tagged `COMPAT(#<PR>)` where they are built.
public enum ServerFeature: String, CaseIterable, Sendable {
    case shifts
    case news
    /// News comments (`comments_count` in `/news`, `GET /news/{id}`) — PR #1710.
    case newsComments
    /// The locations list (`GET /locations`); without PR #1711/#1709 only the `api` group may read it.
    case locationsList
    /// A single location (`GET /locations/{id}`) — PR #1711.
    case locationDetail
    /// Private messages — PR #1720.
    case messages
    case profileWorklogs
    case profileAngelTypes
    /// Goodie score and vouchers of the own profile — PR #1726.
    case profileGoodies
    /// `shift_type.description` on a shift — PR #1722.
    case shiftTypeDescription
    /// The team of a shift with the freeloaded flag — PR #1723.
    case shiftTeam
    /// `sign_out_until` / `can_sign_out` — PR #1722/#1723.
    case signOutDeadline
    /// `GET /shifts/{id}` — PR #1724.
    case singleShiftRefresh

    /// The functions the app uses today, in the order of the instance's "Features" list. The
    /// list grows with the shift detail work (backlog S-01 – S-05).
    public static let listed: [ServerFeature] = [
        .shifts, .news, .newsComments, .locationsList, .locationDetail, .messages, .profileWorklogs, .profileAngelTypes,
        .shiftTypeDescription, .shiftTeam, .signOutDeadline,
    ]

    public var title: String {
        switch self {
        case .shifts: return "Shifts"
        case .news: return "News"
        case .newsComments: return "News comments"
        case .locationsList: return "Locations"
        case .locationDetail: return "Location details"
        case .messages: return "Messages"
        case .profileWorklogs: return "Work logs"
        case .profileAngelTypes: return "Angel types"
        case .profileGoodies: return "Goodie score and vouchers"
        case .shiftTypeDescription: return "Shift type description"
        case .shiftTeam: return "Shift team"
        case .signOutDeadline: return "Sign-out deadline"
        case .singleShiftRefresh: return "Refresh a single shift"
        }
    }

    /// The web privilege that lets an account without the `api` privilege use the function
    /// (`privileges` of `GET /users/self`, PR #1709); nil when any authenticated user may.
    public var requiredPrivilege: String? {
        switch self {
        case .shifts, .profileWorklogs, .profileAngelTypes, .profileGoodies: return nil
        case .news, .newsComments: return "news"
        case .locationsList, .locationDetail: return "locations.view"
        case .messages: return "user_messages"
        case .shiftTypeDescription, .shiftTeam, .signOutDeadline, .singleShiftRefresh: return "user_shifts"
        }
    }
}

/// What is known about a function on one instance.
public enum FeatureState: String, Codable, Sendable {
    case available
    /// The server knows the function, the account may not use it (403, or the privilege is missing).
    case notAllowed
    /// The server does not have the function (404, or the field is missing): an older Engelsystem.
    case notOffered
    case unknown
}

/// Where a `FeatureState` came from.
public enum FeatureEvidence: String, Codable, Sendable {
    case privileges, field, notFound, forbidden, probe
}

public struct FeatureStatus: Equatable, Codable, Sendable {
    public var state: FeatureState
    public var evidence: FeatureEvidence
    /// The privilege the function needs, when it is known why it is not allowed.
    public var privilege: String?
    public var checkedAt: Date?

    public init(state: FeatureState, evidence: FeatureEvidence, privilege: String? = nil, checkedAt: Date? = nil) {
        self.state = state
        self.evidence = evidence
        self.privilege = privilege
        self.checkedAt = checkedAt
    }

    public static let unknown = FeatureStatus(state: .unknown, evidence: .probe, privilege: nil, checkedAt: nil)
}

/// What each instance's server offers and its account may use, learned for free from the normal
/// syncs and from the `privileges` of `GET /users/self`. **Device-local** (`UserDefaults`, not
/// CloudKit): no schema change, each device learns it from its own syncs. Unknown means
/// "available" — the UI only hides a function after something proved it is not usable.
/// `@Observable` so SwiftUI shows/hides affected UI as soon as a sync records a change.
@MainActor
@Observable
public final class ServerCapabilities {
    public static let shared = ServerCapabilities()

    static let defaultsKey = "instanceFeatureStatus"
    /// The first version stored `[key: Bool]` here; read once for migration.
    static let legacyDefaultsKey = "serverCapabilities"

    @ObservationIgnored private let defaults: UserDefaults
    private var values: [String: FeatureStatus]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let stored = try? JSONDecoder().decode([String: FeatureStatus].self, from: data) {
            self.values = stored
        } else {
            let legacy = (defaults.dictionary(forKey: Self.legacyDefaultsKey) as? [String: Bool]) ?? [:]
            self.values = legacy.mapValues {
                FeatureStatus(state: $0 ? .available : .notOffered, evidence: .probe, privilege: nil, checkedAt: nil)
            }
        }
    }

    private static func key(_ feature: ServerFeature, _ instanceID: UUID) -> String {
        instanceID.uuidString + "/" + feature.rawValue
    }

    private func persist() {
        // `[String: FeatureStatus]` is plain Codable, encoding cannot fail.
        defaults.set(try? JSONEncoder().encode(values), forKey: Self.defaultsKey)
    }

    public func status(_ feature: ServerFeature, for instanceID: UUID) -> FeatureStatus {
        values[Self.key(feature, instanceID)] ?? .unknown
    }

    /// `false` only once something showed that the function cannot be used on the instance.
    public func isAvailable(_ feature: ServerFeature, for instanceID: UUID) -> Bool {
        ![FeatureState.notAllowed, .notOffered].contains(status(feature, for: instanceID).state)
    }

    /// How many functions are known to be available out of all of them ("5 of 13").
    public func summary(for instanceID: UUID) -> (available: Int, total: Int) {
        let available = ServerFeature.listed.filter { status($0, for: instanceID).state == .available }.count
        return (available, ServerFeature.listed.count)
    }

    /// Whether the function is available on at least one of the given instances.
    public func isAvailable(_ feature: ServerFeature, forAnyOf instanceIDs: [UUID]) -> Bool {
        instanceIDs.contains { isAvailable(feature, for: $0) }
    }

    /// Remembers a finding. `.unknown` ("could not tell", e.g. an empty news list) leaves the
    /// previous knowledge untouched.
    public func record(
        _ feature: ServerFeature, state: FeatureState, evidence: FeatureEvidence,
        privilege: String? = nil, for instanceID: UUID, now: Date = Date()
    ) {
        guard state != .unknown else { return }
        values[Self.key(feature, instanceID)] = FeatureStatus(
            state: state, evidence: evidence, privilege: privilege, checkedAt: now)
        persist()
    }

    /// Shorthand for the probes that only know "works" / "does not": `nil` changes nothing.
    public func record(_ feature: ServerFeature, supported: Bool?, for instanceID: UUID) {
        guard let supported else { return }
        record(feature, state: supported ? .available : .notOffered, evidence: .probe, for: instanceID)
    }

    /// Records the outcome of a failed request for `feature`: 403 ⇒ not allowed, 404 ⇒ not
    /// offered. Returns whether the failure was one of those two (anything else is a real error).
    @discardableResult
    public func record(_ feature: ServerFeature, afterFailure error: APIError, for instanceID: UUID) -> Bool {
        switch error {
        case .forbidden:
            record(feature, state: .notAllowed, evidence: .forbidden, privilege: feature.requiredPrivilege, for: instanceID)
            return true
        case .notFound:
            record(feature, state: .notOffered, evidence: .notFound, for: instanceID)
            return true
        default:
            return false
        }
    }

    /// Applies the `privileges` of `GET /users/self` (PR #1709). `nil` (an older server without the
    /// field) changes nothing. The `api` privilege reads everything; otherwise the function's web
    /// privilege decides. Functions without a required privilege are not touched.
    public func applyPrivileges(_ privileges: [String]?, for instanceID: UUID, now: Date = Date()) {
        guard let privileges else { return }
        for feature in ServerFeature.allCases {
            guard let required = feature.requiredPrivilege else { continue }
            let granted = !Set(privileges).isDisjoint(with: [required, "api"])
            record(feature, state: granted ? .available : .notAllowed, evidence: .privileges,
                   privilege: granted ? nil : required, for: instanceID, now: now)
        }
    }

    /// "5 of 8 features available" — the one-line summary shown after "Test Connection".
    public static func summaryText(available: Int, total: Int) -> String {
        "\(available) of \(total) features available"
    }

    /// The summary for the account's `privileges` (`GET /users/self`, PR #1709); nil when the
    /// server does not tell (an older Engelsystem) — nothing is claimed then.
    public static func featureSummary(privileges: [String]?) -> String? {
        guard let privileges else { return nil }
        let available = ServerFeature.listed.filter { feature in
            guard let required = feature.requiredPrivilege else { return true }
            return !Set(privileges).isDisjoint(with: [required, "api"])
        }.count
        return summaryText(available: available, total: ServerFeature.listed.count)
    }

    /// Records the outcome of a failed request for `feature`; see `record(_:afterFailure:for:)`.
    /// Anything that is not an `APIError` is a real error.
    @discardableResult
    public func record(_ feature: ServerFeature, afterError error: Error, for instanceID: UUID) -> Bool {
        guard let apiError = error as? APIError else { return false }
        return record(feature, afterFailure: apiError, for: instanceID)
    }

    /// `COMPAT(#1710)`: a server supports news comments exactly when its `/news` items carry
    /// `comments_count`. An empty list says nothing (`nil`).
    public static func newsCommentsSupported(by items: [News]) -> Bool? {
        guard !items.isEmpty else { return nil }
        return items.contains { $0.commentsCount != nil }
    }

    /// `COMPAT(#1722)`/`COMPAT(#1723)`: which shift detail fields the server sends, read from the
    /// synced shifts. An empty list says nothing (no entries). The sign-out deadline and the team
    /// flags are judged on the first shift that has entries/the field's carrier.
    public static func shiftFeaturesSupported(by shifts: [Shift]) -> [ServerFeature: Bool] {
        guard !shifts.isEmpty else { return [:] }
        var result: [ServerFeature: Bool] = [
            .shiftTypeDescription: shifts.contains { $0.shiftType.description != nil },
            .signOutDeadline: shifts.contains { $0.signOutUntil != nil } || shifts.contains { shift in
                shift.neededAngelTypes.contains { $0.entries.contains { $0.canSignOut != nil } }
            },
        ]
        let entries = shifts.flatMap { $0.neededAngelTypes.flatMap(\.entries) }
        if !entries.isEmpty { result[.shiftTeam] = entries.contains { $0.freeloaded != nil } }
        return result
    }
}
