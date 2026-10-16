#if DEBUG
import Foundation

/// A server of a given vintage for the compatibility matrix (backlog K-13, ADR 0015): which upstream
/// PRs it has and what the account may use. `install()` routes the stubbed network with real JSON —
/// the demo data plus the fields and endpoints each PR adds — so tests exercise the same decoding and
/// the same 403/404 paths as a real server. Tests using this must be `.serialized` (see `StubURLProtocol`).
public struct ServerFixture: Sendable {
    public var name: String
    /// `privileges` of `GET /users/self` (PR #1709); `nil` = the field is absent (a server without it).
    public var privileges: [String]?
    /// PR #1710: `comments_count` on news items.
    public var newsComments = false
    /// PR #1711: `GET /locations/{id}`.
    public var locationDetail = false
    /// PR #1720: the messages endpoints exist (otherwise 404).
    public var messages = false
    /// PR #1722: `shift_type.description`, `sign_out_until`, ... on shifts.
    public var shiftDetails = false
    /// PR #1723: entry details (`freeloaded`, `can_sign_out`, ...).
    public var entryDetails = false
    /// PR #1724: `GET /shifts/{id}`.
    public var singleShift = false
    /// PR #1726: `goodie_score`, `vouchers`, ... on the own profile.
    public var profileExtras = false

    public static let apiPrivileges = ["api"]
    public static let angelPrivileges = ["news", "locations.view", "user_shifts", "angeltypes.view", "user_messages"]

    public init(name: String, privileges: [String]? = nil) {
        self.name = name
        self.privileges = privileges
    }

    /// Upstream `main` without any of the open PRs; the account is read-only (`api` group).
    public static let upstreamToday = ServerFixture(name: "upstream main today")

    /// Upstream plus exactly one PR.
    public static func with(pr: Int, privileges: [String]? = nil) -> ServerFixture {
        var fixture = ServerFixture(name: "upstream + #\(pr)", privileges: privileges)
        switch pr {
        case 1709: fixture.privileges = privileges ?? apiPrivileges
        case 1710: fixture.newsComments = true
        case 1711: fixture.locationDetail = true
        case 1720: fixture.messages = true
        case 1722: fixture.shiftDetails = true
        case 1723: fixture.entryDetails = true
        case 1724: fixture.singleShift = true
        case 1726: fixture.profileExtras = true
        default: break
        }
        return fixture
    }

    /// The stacked shift chain #1722 → #1723 → #1724 (each PR is based on the previous one).
    public static let shiftChain: ServerFixture = {
        var fixture = ServerFixture(name: "#1722 + #1723 + #1724")
        fixture.shiftDetails = true
        fixture.entryDetails = true
        fixture.singleShift = true
        return fixture
    }()

    /// Every PR of the stack merged, for an account with the default "Angel" privileges.
    public static let allPRs: ServerFixture = {
        var fixture = ServerFixture(name: "all PRs", privileges: angelPrivileges)
        fixture.newsComments = true
        fixture.locationDetail = true
        fixture.messages = true
        fixture.shiftDetails = true
        fixture.entryDetails = true
        fixture.singleShift = true
        fixture.profileExtras = true
        return fixture
    }()

    /// The same server for an account that holds only these privileges (`nil` = no `privileges` field).
    public func account(privileges: [String]?) -> ServerFixture {
        var copy = self
        copy.privileges = privileges
        return copy
    }

    /// What the account may read: without the `privileges` field every authenticated account is
    /// treated as read-only (`api`), which reads everything an older server exposes.
    private func mayUse(_ privilege: String) -> Bool {
        let held = Set(privileges ?? Self.apiPrivileges)
        return !held.isDisjoint(with: [privilege, "api"])
    }

    private static let prefix = "/api/v0-beta"

    /// Routes every endpoint the sync uses; `reset()` the routes first (`StubbedNetwork.install()`).
    public func install() throws {
        func route(_ path: String, privilege: String?, json: [String: Any]?) throws {
            let key = "GET \(Self.prefix)\(path)"
            if let privilege, !mayUse(privilege) {
                StubURLProtocol.route(key, status: 403, body: Data(#"{"message":"Forbidden"}"#.utf8))
            } else if let json {
                let data = try JSONSerialization.data(withJSONObject: ["data": json["data"] as Any])
                StubURLProtocol.route(key, body: data)
            } else {
                StubURLProtocol.route(key, status: 404, body: Data(#"{"message":"Not implemented"}"#.utf8))
            }
        }

        try route("/users/self/shifts", privilege: nil, json: try shiftsJSON())
        try route("/news", privilege: "news", json: try newsJSON())
        try route("/users/self", privilege: nil, json: try profileJSON())
        try route("/users/self/worklogs", privilege: nil, json: try wrapped(DemoData.worklogs))
        try route("/users/self/angeltypes", privilege: nil, json: try wrapped(DemoData.ownAngelTypes))
        try route("/locations", privilege: "locations.view", json: try wrapped(DemoData.locations))
        if locationDetail, mayUse("locations.view") {
            try StubURLProtocol.route("GET \(Self.prefix)/locations/1", data: DemoData.location(id: 1))
        }
        if singleShift {
            let shift = try shiftsJSON()["data"] as? [[String: Any]]
            if let first = shift?.first {
                StubURLProtocol.route(
                    "GET \(Self.prefix)/shifts/1", body: try JSONSerialization.data(withJSONObject: ["data": first]))
            }
        }
        if messages {
            try route("/messages", privilege: "user_messages", json: try wrapped([Conversation]()))
        } else {
            try route("/messages", privilege: nil, json: nil)
        }
    }

    // MARK: JSON

    private func wrapped<T: Encodable>(_ value: T) throws -> [String: Any] {
        let encoded = try CodableHelper.jsonEncoder.encode(value)
        let object = try JSONSerialization.jsonObject(with: encoded, options: [.fragmentsAllowed])
        return ["data": object]
    }

    private func mutate(_ wrappedValue: [String: Any], _ change: (inout [String: Any]) -> Void) -> [String: Any] {
        guard var items = wrappedValue["data"] as? [[String: Any]] else { return wrappedValue }
        for index in items.indices { change(&items[index]) }
        return ["data": items]
    }

    func shiftsJSON() throws -> [String: Any] {
        mutate(try wrapped(DemoData.shifts)) { shift in
            var type = shift["shift_type"] as? [String: Any] ?? [:]
            if shiftDetails {
                type["description"] = "What this shift is about."
                shift["sign_out_until"] = "2026-12-27T08:00:00+01:00"
                shift["signup_available_from"] = NSNull()
                shift["tags"] = [["id": 1, "name": "TestTag"]]
                shift["talk_url"] = NSNull()
                shift["night_shift"] = false
            } else {
                for key in ["sign_out_until", "signup_available_from", "tags", "talk_url", "night_shift"] {
                    shift[key] = nil
                }
                type["description"] = nil
            }
            shift["shift_type"] = type

            // The demo team carries every entry field; strip what this server does not have.
            var needed = shift["needed_angel_types"] as? [[String: Any]] ?? []
            for typeIndex in needed.indices {
                var entries = needed[typeIndex]["entries"] as? [[String: Any]] ?? []
                for index in entries.indices {
                    if !entryDetails {
                        for key in ["freeloaded", "can_sign_out", "user_comment", "freeloaded_comment"] {
                            entries[index][key] = nil
                        }
                    }
                    if privileges?.contains("api") != true, privileges != nil { entries[index]["freeloaded_by"] = nil }
                }
                needed[typeIndex]["entries"] = entries
            }
            shift["needed_angel_types"] = needed
        }
    }

    func newsJSON() throws -> [String: Any] {
        mutate(try wrapped(DemoData.news)) { item in
            if !newsComments { item["comments_count"] = nil }
        }
    }

    func profileJSON() throws -> [String: Any] {
        var profile = try wrapped(DemoData.ownProfile)
        guard var data = profile["data"] as? [String: Any] else { return profile }
        if let privileges {
            data["privileges"] = privileges
            data["groups"] = [["id": 1, "name": "Angel"]]
        }
        if profileExtras {
            data["goodie_score"] = 12
            data["vouchers"] = 1
        }
        profile["data"] = data
        return profile
    }
}
#endif
