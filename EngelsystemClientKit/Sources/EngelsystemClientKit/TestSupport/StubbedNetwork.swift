#if DEBUG
import Foundation

/// Test infrastructure, compiled into Debug builds only (`#if DEBUG`, so Release/App Store builds do
/// not contain it) and shared by every test target (Kit, iOS app, Watch app) — a separate test-support
/// package would link a second copy of the Kit into the test bundle and so swap the generator's globals
/// in the wrong copy. Routes the generated API client's requests to canned responses instead of the network,
/// so `APIClient`'s real (non-demo) code path can be tested. The generator's
/// `EngelsystemAPIAPI.requestBuilderFactory` is the supported injection point: the builders
/// below only override which `URLSession` is used. Tests using this must be `.serialized`
/// (the factory and routes are process-wide state, like the generator's own `basePath`).
public final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    public struct Response {
        public var status: Int
        public var body: Data
        public var delay: TimeInterval = 0
    }

    public nonisolated(unsafe) static var routes: [String: Response] = [:]
    public nonisolated(unsafe) static var requests: [URLRequest] = []
    private static let lock = NSLock()

    public static func reset() {
        lock.lock(); defer { lock.unlock() }
        routes = [:]
        requests = []
    }

    public static func route(_ key: String, status: Int = 200, body: Data = Data("{}".utf8), delay: TimeInterval = 0) {
        lock.lock(); defer { lock.unlock() }
        routes[key] = Response(status: status, body: body, delay: delay)
    }

    public static func route<T: Encodable>(_ key: String, status: Int = 200, data value: T) throws {
        let encoded = try CodableHelper.jsonEncoder.encode(value)
        route(key, status: status, body: Data("{\"data\":".utf8) + encoded + Data("}".utf8))
    }

    /// Routes `key` to the demo event info / the demo user's own profile, so app test targets
    /// (which cannot see the internal `DemoData`) can stub a *valid* `/info` or `/users/self`.
    public static func routeDemoInfo(_ key: String) throws { try route(key, data: DemoData.info) }
    public static func routeDemoOwnProfile(_ key: String) throws { try route(key, data: DemoData.ownProfile) }

    public static var recorded: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return requests
    }

    public override class func canInit(with request: URLRequest) -> Bool { true }
    public override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    public override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let key = "\(request.httpMethod ?? "GET") \(request.url?.path ?? "")"
        let response = Self.routes[key]
        Self.lock.unlock()

        if let delay = response?.delay, delay > 0 { Thread.sleep(forTimeInterval: delay) }
        let status = response?.status ?? 404
        let body = response?.body ?? Data(#"{"message":"Not implemented"}"#.utf8)
        let http = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    public override func stopLoading() {}
}

public enum StubbedNetwork {
    public static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }()

    public static let credential = EventCredential(baseURL: "https://stub.test", apiKey: "secret-key")

    public static func install() {
        StubURLProtocol.reset()
        EngelsystemAPIAPI.requestBuilderFactory = StubRequestBuilderFactory()
        EngelsystemAPIAPI.apiResponseQueue = DispatchQueue(label: "stubbed-network.response")
    }
}

public struct StubRequestBuilderFactory: RequestBuilderFactory {
    public init() {}
    public func getNonDecodableBuilder<T>() -> RequestBuilder<T>.Type { StubRequestBuilder<T>.self }
    public func getBuilder<T: Decodable>() -> RequestBuilder<T>.Type { StubDecodableRequestBuilder<T>.self }
}

public final class StubRequestBuilder<T>: URLSessionRequestBuilder<T>, @unchecked Sendable {
    public override func createURLSession() -> URLSessionProtocol { StubbedNetwork.session }
}

public final class StubDecodableRequestBuilder<T: Decodable>: URLSessionDecodableRequestBuilder<T>, @unchecked Sendable {
    public override func createURLSession() -> URLSessionProtocol { StubbedNetwork.session }
}
#endif
