import Foundation
import Testing
@testable import EngelsystemClientKit

/// Routes the generated API client's requests to canned responses instead of the network,
/// so `APIClient`'s real (non-demo) code path can be tested. The generator's
/// `EngelsystemAPIAPI.requestBuilderFactory` is the supported injection point: the builders
/// below only override which `URLSession` is used. Tests using this must be `.serialized`
/// (the factory and routes are process-wide state, like the generator's own `basePath`).
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response {
        var status: Int
        var body: Data
        var delay: TimeInterval = 0
    }

    nonisolated(unsafe) static var routes: [String: Response] = [:]
    nonisolated(unsafe) static var requests: [URLRequest] = []
    private static let lock = NSLock()

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        routes = [:]
        requests = []
    }

    static func route(_ key: String, status: Int = 200, body: Data = Data("{}".utf8), delay: TimeInterval = 0) {
        lock.lock(); defer { lock.unlock() }
        routes[key] = Response(status: status, body: body, delay: delay)
    }

    static func route<T: Encodable>(_ key: String, status: Int = 200, data value: T) throws {
        let encoded = try CodableHelper.jsonEncoder.encode(value)
        route(key, status: status, body: Data("{\"data\":".utf8) + encoded + Data("}".utf8))
    }

    static var recorded: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return requests
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
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

    override func stopLoading() {}
}

enum StubbedNetwork {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }()

    static let credential = EventCredential(baseURL: "https://stub.test", apiKey: "secret-key")

    static func install() {
        StubURLProtocol.reset()
        EngelsystemAPIAPI.requestBuilderFactory = StubRequestBuilderFactory()
        EngelsystemAPIAPI.apiResponseQueue = DispatchQueue(label: "stubbed-network.response")
    }
}

struct StubRequestBuilderFactory: RequestBuilderFactory {
    func getNonDecodableBuilder<T>() -> RequestBuilder<T>.Type { StubRequestBuilder<T>.self }
    func getBuilder<T: Decodable>() -> RequestBuilder<T>.Type { StubDecodableRequestBuilder<T>.self }
}

final class StubRequestBuilder<T>: URLSessionRequestBuilder<T>, @unchecked Sendable {
    override func createURLSession() -> URLSessionProtocol { StubbedNetwork.session }
}

final class StubDecodableRequestBuilder<T: Decodable>: URLSessionDecodableRequestBuilder<T>, @unchecked Sendable {
    override func createURLSession() -> URLSessionProtocol { StubbedNetwork.session }
}

/// Parent of every suite that uses `StubbedNetwork`: they all share process-wide state (the
/// generator's request builder factory and the stub routes), so they must never run in
/// parallel with each other. `.serialized` applies to the nested suites too.
@Suite(.serialized)
struct StubbedNetworkTests {}
