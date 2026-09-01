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
        return try await withCredential(credential) {
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
        return try await withCredentialList(credential) {
            try await NewsAPI.newsGet().data ?? []
        }
    }

    public func fetchAngelTypes(_ credential: EventCredential) async throws -> [AngelType] {
        if credential.isDemo {
            await DemoData.simulateLatency()
            return DemoData.angelTypes
        }
        return try await withCredentialList(credential) {
            try await AngelTypeAPI.angeltypesGet().data ?? []
        }
    }

    public func fetchLocations(_ credential: EventCredential) async throws -> [Location] {
        if credential.isDemo {
            await DemoData.simulateLatency()
            return DemoData.locations
        }
        return try await withCredentialList(credential) {
            try await LocationAPI.locationsGet().data ?? []
        }
    }

    public func fetchShiftTypes(_ credential: EventCredential) async throws -> [ShiftType] {
        if credential.isDemo {
            await DemoData.simulateLatency()
            return DemoData.shiftTypes
        }
        return try await withCredentialList(credential) {
            try await ShiftTypeAPI.shifttypesGet().data ?? []
        }
    }

    public func fetchShifts(for user: UserReference, _ credential: EventCredential) async throws -> [Shift] {
        if credential.isDemo {
            await DemoData.simulateLatency()
            return DemoData.shifts
        }
        return try await withCredentialList(credential) {
            try await ShiftAPI.usersIdShiftsGet(id: user.parameter).data ?? []
        }
    }

    public func fetchWorklogs(for user: UserReference, _ credential: EventCredential) async throws -> [Worklog] {
        if credential.isDemo {
            await DemoData.simulateLatency()
            return DemoData.worklogs
        }
        return try await withCredentialList(credential) {
            try await WorklogAPI.usersIdWorklogsGet(id: user.parameter).data ?? []
        }
    }

    public func fetchOwnProfile(_ credential: EventCredential) async throws -> UsersIdGet200ResponseData {
        if credential.isDemo {
            await DemoData.simulateLatency()
            return DemoData.ownProfile
        }
        return try await withCredential(credential) {
            guard let data = try await UserAPI.usersIdGet(id: UserReference.me.parameter).data else {
                throw APIError.decoding("Missing data in /users/self response")
            }
            return data
        }
    }

    /// For endpoints where, per project spec, missing data is treated as an empty
    /// list instead of an error (404 → empty list).
    private func withCredentialList<T>(_ credential: EventCredential, _ operation: @Sendable () async throws -> [T]) async throws -> [T] {
        do {
            return try await withCredential(credential, operation)
        } catch APIError.notFound {
            return []
        }
    }

    private func withCredential<T>(_ credential: EventCredential, _ operation: @Sendable () async throws -> T) async throws -> T {
        guard !credential.baseURL.isEmpty, URL(string: credential.baseURL) != nil else {
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
            throw APIError(error)
        }
    }
}
