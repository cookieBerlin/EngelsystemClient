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
    var isDemo: Bool { baseURL.hasPrefix(DemoScenario.scheme) }

    /// The demo data set of this address; nil for a `demo://` address with an unknown host.
    var demoScenario: DemoScenario? { DemoScenario(baseURL: baseURL) }

    /// The data set to serve; an unknown demo host gets the instance that names the addresses that work.
    var scenario: DemoScenario { demoScenario ?? .unknown }
}

public final class APIClient {
    public static let shared = APIClient()

    private let gate = RequestGate()

    public init() {}

    public func fetchInfo(_ credential: EventCredential) async throws -> EventInfo {
        if credential.isDemo {
            await DemoData.simulateLatency()
            return DemoData.info(for: credential.scenario)
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
            return DemoData.news(for: credential.scenario)
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
            guard let detail = DemoData.newsDetail(id: id, for: credential.scenario) else {
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
    public func fetchOwnAngelTypes(_ credential: EventCredential) async throws -> [UserAngelType] {
        if credential.isDemo {
            await DemoData.simulateLatency()
            return DemoData.ownAngelTypes
        }
        return try await withCredentialList("GET /users/self/angeltypes", credential) {
            try await UserAPI.usersIdAngeltypesGet(id: .me).data ?? []
        }
    }

    public func fetchLocations(_ credential: EventCredential) async throws -> [Location] {
        if credential.isDemo {
            await DemoData.simulateLatency()
            return DemoData.locations(for: credential.scenario)
        }
        return try await withCredentialList("GET /locations", credential) {
            try await LocationAPI.locationsGet().data ?? []
        }
    }

    /// A single shift, fetched live (`GET /shifts/{id}`) — backs the shift detail page's pull to
    /// refresh. COMPAT(#1724): servers without the endpoint answer 404, which is a "not offered"
    /// finding for the caller, not an empty result.
    public func fetchShift(id: Int, _ credential: EventCredential) async throws -> Shift {
        if credential.isDemo {
            await DemoData.simulateLatency()
            guard let shift = DemoData.shifts(for: credential.scenario).first(where: { $0.id == id }) else { throw APIError.notFound }
            return shift
        }
        return try await withCredential("GET /shifts/\(id)", credential) {
            guard let data = try await ShiftAPI.shiftsIdGet(id: id).data else {
                throw APIError.decoding("Missing data in /shifts/{id} response")
            }
            return data
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
            guard let location = DemoData.location(id: id, for: credential.scenario) else {
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

    public func fetchShifts(_ credential: EventCredential) async throws -> [Shift] {
        if credential.isDemo {
            await DemoData.simulateLatency()
            return DemoData.shifts(for: credential.scenario)
        }
        return try await withCredentialList("GET /users/self/shifts", credential) {
            try await ShiftAPI.usersIdShiftsGet(id: .me).data ?? []
        }
    }

    public func fetchWorklogs(_ credential: EventCredential) async throws -> [Worklog] {
        if credential.isDemo {
            await DemoData.simulateLatency()
            return DemoData.worklogs
        }
        return try await withCredentialList("GET /users/self/worklogs", credential) {
            try await WorklogAPI.usersIdWorklogsGet(id: .me).data ?? []
        }
    }

    /// COMPAT(#1709): the account's `privileges` from `GET /users/self` (only servers with PR #1709
    /// send them). `nil` for an older server or any failure — nothing is concluded then. Demo mode
    /// reads everything. Used by "Test Connection" for the features summary.
    public func ownPrivileges(_ credential: EventCredential) async -> [String]? {
        if credential.isDemo {
            return ["api"]
        }
        let profile = try? await withCredential("GET /users/self (privileges)", credential) {
            try await UserAPI.usersIdGet(id: .me).data
        }
        return profile?.privileges
    }

    public func fetchOwnProfile(_ credential: EventCredential) async throws -> UsersIdGet200ResponseData {
        if credential.isDemo {
            await DemoData.simulateLatency()
            return DemoData.ownProfile
        }
        return try await withCredential("GET /users/self", credential) {
            guard let data = try await UserAPI.usersIdGet(id: .me).data else {
                throw APIError.decoding("Missing data in /users/{id} response")
            }
            return data
        }
    }

    /// Every user on the instance — `GET /users` — backs the "start a new
    /// conversation" picker (2026-09-23, Messages feature). Distinct from
    /// `fetchOwnProfile`/`fetchOwnAngelTypes`, which are always about the signed-in
    /// user specifically.
    public func fetchUsers(_ credential: EventCredential) async throws -> [Reference] {
        if credential.isDemo {
            await DemoData.simulateLatency()
            return DemoData.users
        }
        return try await withCredentialList("GET /users", credential) {
            try await UserAPI.usersGet().data ?? []
        }
    }

    // MARK: - Messages (2026-09-23)
    //
    // The first write feature in this API (previously 100% GET-only) — added on a
    // server branch not yet merged upstream (feat/api-messages, cross-session
    // sourced, verified against the real server implementation rather than guessed —
    // see docs/architecture.md). Deliberately live-only: no `Cached*` model, no
    // `XSyncService` — every method here hits the network every time it's called,
    // matching `fetchNewsDetail`'s comments (not `fetchShifts`'s cached-list shape),
    // since this is this app's first *mutable*, bidirectional data and avoiding a
    // local cache sidesteps a whole class of offline-write-conflict problems for a
    // first version.

    /// Every conversation the signed-in user is part of — `GET /messages`. Unlike
    /// `fetchLocations`/`fetchAngelTypes`, a 404 here is a genuine error (the server
    /// doesn't support Messages at all), never "empty" — a real empty inbox is `200`
    /// with `{"data": []}` — so this goes through `withCredential`, not
    /// `withCredentialList`, matching `fetchNewsDetail`/`fetchLocation`.
    public func fetchConversations(_ credential: EventCredential) async throws -> [Conversation] {
        if credential.isDemo {
            await DemoData.simulateLatency()
            return await DemoData.conversations()
        }
        return try await withCredential("GET /messages", credential) {
            try await MessageAPI.messagesGet().data ?? []
        }
    }

    /// Every message exchanged with one specific user, oldest first per the API docs
    /// — `GET /messages/{id}`, where `id` is the *other user's* id (not a message id).
    public func fetchConversation(otherUserID: Int, _ credential: EventCredential) async throws -> [Message] {
        if credential.isDemo {
            await DemoData.simulateLatency()
            return await DemoData.conversation(otherUserID: otherUserID)
        }
        return try await withCredential("GET /messages/{id}", credential) {
            guard let data = try await MessageAPI.messagesIdGet(id: otherUserID).data else {
                throw APIError.decoding("Missing data in /messages/{id} response")
            }
            return data.messages ?? []
        }
    }

    /// Sends a message to the given user — `POST /messages/{id}`, `201` with the
    /// created `Message` on success.
    public func sendMessage(to otherUserID: Int, text: String, _ credential: EventCredential) async throws -> Message {
        if credential.isDemo {
            await DemoData.simulateLatency()
            return await DemoData.sendMessage(to: otherUserID, text: text)
        }
        return try await withCredential("POST /messages/{id}", credential) {
            guard let data = try await MessageAPI.messagesIdPost(id: otherUserID, messageSend: MessageSend(text: text)).data else {
                throw APIError.decoding("Missing data in POST /messages/{id} response")
            }
            return data
        }
    }

    /// Deletes a message the signed-in user sent — `DELETE /messages/{msgId}`, `204`
    /// on success, `403` if it isn't yours (surfaced as `APIError.forbidden`).
    public func deleteMessage(id: Int, _ credential: EventCredential) async throws {
        if credential.isDemo {
            await DemoData.simulateLatency()
            await DemoData.deleteMessage(id: id)
            return
        }
        try await withCredential("DELETE /messages/{msgId}", credential) {
            try await MessageAPI.messagesMsgIdDelete(msgId: id)
        }
    }

    /// Sets or clears a message's read status — `PATCH /messages/{msgId}`. Only the
    /// *receiver* of a message may do this (`403` for the sender) — used both for an
    /// explicit "mark unread" affordance and to auto-mark a conversation's incoming
    /// messages read when it's opened (`ConversationDetailViewModel`).
    public func setMessageRead(id: Int, read: Bool, _ credential: EventCredential) async throws -> Message {
        if credential.isDemo {
            await DemoData.simulateLatency()
            guard let updated = await DemoData.setMessageRead(id: id, read: read) else {
                throw APIError.notFound
            }
            return updated
        }
        return try await withCredential("PATCH /messages/{msgId}", credential) {
            guard let data = try await MessageAPI.messagesMsgIdPatch(msgId: id, messageSetRead: MessageSetRead(read: read)).data else {
                throw APIError.decoding("Missing data in PATCH /messages/{msgId} response")
            }
            return data
        }
    }

    /// COMPAT(#1720): probes whether this instance's server supports the Messages API at all —
    /// backs `Instance.messagesSupported`, which gates whether the whole Messages
    /// sidebar entry shows up (2026-09-23, user-requested: "if the instance doesn't
    /// offer the new interface, don't show the GUI"). Demo credential always reports
    /// `true`.
    ///
    /// A plain `GET /messages` with no special handling would be ambiguous: a 404
    /// there could mean either "this route doesn't exist on this server" (unsupported)
    /// or something else — the two are only distinguishable by the response *body*,
    /// which `APIError`'s unified shape doesn't preserve (see `withLockedCredential`).
    /// So this calls that directly instead of going through `withCredential`.
    public func messagesSupported(_ credential: EventCredential) async -> Bool {
        await messagesState(credential) != .notOffered
    }

    /// Like `messagesSupported(_:)`, but tells a route the account may not use (403) from a usable
    /// one: `.available`, `.notAllowed` (route exists, 403) or `.notOffered` (route missing).
    public func messagesState(_ credential: EventCredential) async -> FeatureState {
        if credential.isDemo { return .available }
        guard !credential.baseURL.isEmpty, URL(string: credential.baseURL) != nil else { return .available }
        do {
            _ = try await withLockedCredential(credential) {
                try await MessageAPI.messagesGet().data
            }
            DebugLog.log("API GET /messages (capability probe) → supported")
            return .available
        } catch {
            let state = Self.messagesState(afterProbeError: error)
            DebugLog.log("API GET /messages (capability probe) → \(state.rawValue) (\(error))")
            return state
        }
    }

    /// The pure "how to interpret the probe's outcome" logic behind
    /// `messagesSupported(_:)`, split out so it's unit-testable without a real network
    /// round trip. Verified against
    /// the real server implementation via a cross-session message, not guessed: two
    /// different situations both return HTTP 404 with *different* JSON bodies — a
    /// route that genuinely doesn't exist falls through to the app's shared catch-all
    /// (`{"message": "Not implemented"}`, not specific to Messages), while a 404 for
    /// a specific resource that just isn't found is `{"message": "Not Found"}`. Any
    /// other outcome (200, or a 403/422/etc. for an unrelated reason) means the route
    /// exists — a missing route never responds with anything but that exact 404 body.
    static func messagesSupported(afterProbeError error: Error) -> Bool {
        messagesState(afterProbeError: error) != .notOffered
    }

    static func messagesState(afterProbeError error: Error) -> FeatureState {
        if let errorResponse = error as? ErrorResponse, case .error(403, _, _, _) = errorResponse {
            return .notAllowed
        }
        return messagesRouteExists(afterProbeError: error) ? .available : .notOffered
    }

    private static func messagesRouteExists(afterProbeError error: Error) -> Bool {
        guard let errorResponse = error as? ErrorResponse,
              case let .error(404, data, _, _) = errorResponse,
              let data,
              let body = try? JSONDecoder().decode(ProbeErrorBody.self, from: data)
        else { return true }
        return body.message != "Not implemented"
    }

    private struct ProbeErrorBody: Decodable {
        let message: String
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

        do {
            return try await withLockedCredential(credential, operation)
        } catch {
            // Cancellation isn't an API/network failure (e.g. a SwiftUI `.task` cancelled
            // because the view it was attached to disappeared) — rethrow it as-is rather
            // than disguising it as `APIError.network(...)`, so callers can tell the two
            // apart and skip showing a "Connection failed" error for it. Not logged as a
            // failure for the same reason — it isn't one.
            // A cancelled URLSession request fails with `URLError.cancelled`, not a `CancellationError`:
            // a cancelled task (Stop sync, skip, timeout) counts as cancellation either way.
            if error is CancellationError || Task.isCancelled {
                throw CancellationError()
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

    /// Locks the shared request gate, sets the credential, runs `operation`, and always
    /// unlocks — rethrows whatever `operation` throws completely unchanged, with no
    /// `APIError` mapping and no logging (unlike `withCredential`, which wraps this).
    /// `messagesSupported(_:)`'s capability probe calls this directly instead of
    /// `withCredential`, since it needs the *raw* `ErrorResponse` (specifically its
    /// response body) to distinguish "route doesn't exist" from any other failure —
    /// something `APIError`'s unified shape deliberately doesn't preserve for any
    /// other caller.
    private func withLockedCredential<T>(_ credential: EventCredential, _ operation: @Sendable () async throws -> T) async throws -> T {
        await gate.lock()
        EngelsystemAPIAPI.basePath = credential.baseURL
        EngelsystemAPIAPI.customHeaders = ["x-api-key": credential.apiKey]

        do {
            let result = try await operation()
            await gate.unlock()
            return result
        } catch {
            await gate.unlock()
            throw error
        }
    }
}
