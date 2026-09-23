import Foundation

/// Serializes access to `EngelsystemAPIAPI.basePath`/`.customHeaders`, which are
/// global shared state due to the generator's design — necessary so that
/// concurrent requests to different instances (multi-instance concept) don't clobber each other.
private actor RequestGate {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func lock() async {
        if !isLocked {
            isLocked = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func unlock() {
        if waiters.isEmpty {
            isLocked = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

public struct EventCredential: Sendable {
    public let baseURL: String
    public let apiKey: String

    public init(baseURL: String, apiKey: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    /// True for the sentinel demo instance (see `Instance.demoBaseURL`) — `APIClient`
    /// returns static mock data for these instead of making a real network request.
    var isDemo: Bool { baseURL.hasPrefix(Instance.demoBaseURL) }
}

public final class APIClient {
    public static let shared = APIClient()

    private let gate = RequestGate()

    public init() {}

    public func fetchInfo(_ credential: EventCredential) async throws -> EventInfo {
        if credential.isDemo {
            await DemoData.simulateLatency()
            return DemoData.info
        }
        return try await withCredential("GET /info", credential) {
            guard let data = try await EventAPI.infoGet().data else {
                throw APIError.decoding("Missing data in /info response")
            }
            return data
        }
    }

    public func fetchNews(_ credential: EventCredential) async throws -> [News] {
        if credential.isDemo {
            await DemoData.simulateLatency()
            return DemoData.news
        }
        return try await withCredentialList("GET /news", credential) {
            try await NewsAPI.newsGet().data ?? []
        }
    }

    /// A single news post's full detail, including its comments (`GET /news/{id}`,
    /// added 2026-09-22). Unlike `fetchNews`, a 404 here is a genuine error (an
    /// unknown/deleted post), not "empty" — so this goes through `withCredential`,
    /// not `withCredentialList`.
    public func fetchNewsDetail(id: Int, _ credential: EventCredential) async throws -> NewsDetail {
        if credential.isDemo {
            await DemoData.simulateLatency()
            guard let detail = DemoData.newsDetail(id: id) else {
                throw APIError.notFound
            }
            return detail
        }
        return try await withCredential("GET /news/\(id)", credential) {
            guard let data = try await NewsAPI.newsIdGet(id: id).data else {
                throw APIError.decoding("Missing data in /news/{id} response")
            }
            return data
        }
    }

    public func fetchAngelTypes(_ credential: EventCredential) async throws -> [AngelType] {
        if credential.isDemo {
            await DemoData.simulateLatency()
            return DemoData.angelTypes
        }
        return try await withCredentialList("GET /angeltypes", credential) {
            try await AngelTypeAPI.angeltypesGet().data ?? []
        }
    }

    /// The signed-in user's own angel type memberships (`GET /users/{id}/angeltypes`) —
    /// not to be confused with `fetchAngelTypes`, which lists the instance-wide catalog.
    public func fetchOwnAngelTypes(for user: UserReference, _ credential: EventCredential) async throws -> [UserAngelType] {
        if credential.isDemo {
            await DemoData.simulateLatency()
            return DemoData.ownAngelTypes
        }
        return try await withCredentialList("GET /users/\(user.parameter)/angeltypes", credential) {
            try await UserAPI.usersIdAngeltypesGet(id: user.parameter).data ?? []
        }
    }

    public func fetchLocations(_ credential: EventCredential) async throws -> [Location] {
        if credential.isDemo {
            await DemoData.simulateLatency()
            return DemoData.locations
        }
        return try await withCredentialList("GET /locations", credential) {
            try await LocationAPI.locationsGet().data ?? []
        }
    }

    /// A single location, fetched live (`GET /locations/{id}`) — backs
    /// `LocationDetailView`'s own pull-to-refresh (2026-09-23), separate from the
    /// cached list `fetchLocations` returns. A 404 here is a genuine error (the
    /// location was deleted server-side), not "empty" — so this goes through
    /// `withCredential`, not `withCredentialList`, matching `fetchNewsDetail`.
    ///
    /// This endpoint didn't exist before 2026-09-23 (only the list did) — it's on a
    /// server branch not yet merged upstream (PR engelsystem/engelsystem#1711), so a
    /// server without it will surface a normal `APIError` here (e.g. `.notFound` or a
    /// route-not-found failure) rather than crashing; the cached-list-based features
    /// (the Locations screen, the link from a shift) never call this and are
    /// unaffected either way.
    public func fetchLocation(id: Int, _ credential: EventCredential) async throws -> Location {
        if credential.isDemo {
            await DemoData.simulateLatency()
            guard let location = DemoData.location(id: id) else {
                throw APIError.notFound
            }
            return location
        }
        return try await withCredential("GET /locations/\(id)", credential) {
            guard let data = try await LocationAPI.locationsIdGet(id: id).data else {
                throw APIError.decoding("Missing data in /locations/{id} response")
            }
            return data
        }
    }

    public func fetchShiftTypes(_ credential: EventCredential) async throws -> [ShiftType] {
        if credential.isDemo {
            await DemoData.simulateLatency()
            return DemoData.shiftTypes
        }
        return try await withCredentialList("GET /shifttypes", credential) {
            try await ShiftTypeAPI.shifttypesGet().data ?? []
        }
    }

    public func fetchShifts(for user: UserReference, _ credential: EventCredential) async throws -> [Shift] {
        if credential.isDemo {
            await DemoData.simulateLatency()
            return DemoData.shifts
        }
        return try await withCredentialList("GET /users/\(user.parameter)/shifts", credential) {
            try await ShiftAPI.usersIdShiftsGet(id: user.parameter).data ?? []
        }
    }

    public func fetchWorklogs(for user: UserReference, _ credential: EventCredential) async throws -> [Worklog] {
        if credential.isDemo {
            await DemoData.simulateLatency()
            return DemoData.worklogs
        }
        return try await withCredentialList("GET /users/\(user.parameter)/worklogs", credential) {
            try await WorklogAPI.usersIdWorklogsGet(id: user.parameter).data ?? []
        }
    }

    /// Probes whether this server actually resolves the `self` user-reference alias,
    /// independent of whatever `UserReference` a caller would otherwise use — always
    /// tests the literal `self` value, so a server that's since been fixed can be
    /// detected even for an `Instance` that already has a manual `userID` fallback
    /// configured (see `Instance.selfReferenceWorks`). Deliberately probes
    /// `/users/self/worklogs` specifically, not `/users/self`: on the one real-world
    /// server implementation bug found for this (2026-09-21, CLAUDE.md), the other
    /// three `self`-capable endpoints always worked — only `/worklogs` ever 404s on an
    /// unpatched server, so it's the only endpoint that actually distinguishes "old,
    /// broken server" from "fixed server". A `404` (`.notFound`) there is a resolution
    /// failure regardless of whether the user has any worklogs at all (PHP's `(int)
    /// "self"` becomes `0`, and looking up user `0` always throws) — never confuse
    /// this with a genuine "no worklogs yet" empty list, which is a `200` either way.
    /// Any outcome other than a definitive `.notFound` (success, or an unrelated error)
    /// is treated as "self works" — a single transient network hiccup during this probe
    /// shouldn't be able to flip the UI into showing the fallback field.
    public func selfUserReferenceWorks(_ credential: EventCredential) async -> Bool {
        if credential.isDemo {
            return true
        }
        do {
            _ = try await withCredential("GET /users/self/worklogs (self-reference probe)", credential) {
                try await WorklogAPI.usersIdWorklogsGet(id: UserReference.me.parameter).data
            }
            return Self.selfWorks(afterProbeError: nil)
        } catch {
            return Self.selfWorks(afterProbeError: error)
        }
    }

    /// The pure "how to interpret the probe's outcome" logic behind
    /// `selfUserReferenceWorks`, split out so it's unit-testable without a real network
    /// round trip (see `EngelsystemClientKitTests`). `nil` means the probe succeeded.
    static func selfWorks(afterProbeError error: Error?) -> Bool {
        guard let error else { return true }
        if case APIError.notFound = error { return false }
        return true
    }

    public func fetchOwnProfile(for user: UserReference, _ credential: EventCredential) async throws -> UsersIdGet200ResponseData {
        if credential.isDemo {
            await DemoData.simulateLatency()
            return DemoData.ownProfile
        }
        return try await withCredential("GET /users/\(user.parameter)", credential) {
            guard let data = try await UserAPI.usersIdGet(id: user.parameter).data else {
                throw APIError.decoding("Missing data in /users/{id} response")
            }
            return data
        }
    }

    /// For endpoints where, per project spec, missing data is treated as an empty
    /// list instead of an error (404 → empty list). Also logs the resulting item
    /// count on success — 2026-09-23, user-requested "check the data flow for
    /// logging gaps": distinct from the per-domain "synced N" logs already in
    /// Shifts/News/ProfileViewModel, since those only run for pull-to-refresh —
    /// this is the one place that also covers app-start/background sync, which go
    /// through `AppSyncCoordinator` directly.
    private func withCredentialList<T>(_ path: String, _ credential: EventCredential, _ operation: @Sendable () async throws -> [T]) async throws -> [T] {
        do {
            let items = try await withCredential(path, credential, operation)
            DebugLog.log("API \(path) → \(items.count) item(s)")
            return items
        } catch APIError.notFound {
            // Distinguishes "server said 404, we're treating that as an empty list" from
            // a genuine 200-with-empty-array in the caller's logs — see CLAUDE.md's open
            // bug about Shifts/Profile showing empty with no error on a real server.
            DebugLog.log("API \(path) → 404, treating as empty list")
            return []
        }
    }

    private func withCredential<T>(_ path: String, _ credential: EventCredential, _ operation: @Sendable () async throws -> T) async throws -> T {
        guard !credential.baseURL.isEmpty, URL(string: credential.baseURL) != nil else {
            DebugLog.log("API \(path) → invalid base URL", level: .error)
            throw APIError.invalidBaseURL
        }

        await gate.lock()
        EngelsystemAPIAPI.basePath = credential.baseURL
        EngelsystemAPIAPI.customHeaders = ["x-api-key": credential.apiKey]

        do {
            let result = try await operation()
            await gate.unlock()
            return result
        } catch {
            await gate.unlock()
            // Cancellation isn't an API/network failure (e.g. a SwiftUI `.task` cancelled
            // because the view it was attached to disappeared) — rethrow it as-is rather
            // than disguising it as `APIError.network(...)`, so callers can tell the two
            // apart and skip showing a "Connection failed" error for it. Not logged as a
            // failure for the same reason — it isn't one.
            if error is CancellationError {
                throw error
            }
            let apiError = APIError(error)
            // For a list endpoint's 404 specifically, `withCredentialList` above logs
            // its own, more informative "treating as empty list" line right after this
            // one — two lines for that one case, which is fine (still says both "this
            // failed" and "here's the recovery"), rather than trying to distinguish
            // the two call shapes here just to avoid it.
            DebugLog.log("API \(path) → failed: \(apiError)", level: .error)
            throw apiError
        }
    }
}
