import Foundation

public enum APIError: Error, Equatable {
    /// 401 — Token/API key is missing or invalid. Caller should go back to Instance Setup.
    case unauthorized
    /// 403 — User doesn't have the `API`/`Bureaucrat` group on the instance.
    case forbidden
    /// 404 — Resource not found.
    case notFound
    case server(statusCode: Int)
    case invalidBaseURL
    case network(String)
    case decoding(String)

    public static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.unauthorized, .unauthorized),
             (.forbidden, .forbidden),
             (.notFound, .notFound),
             (.invalidBaseURL, .invalidBaseURL):
            return true
        case let (.server(a), .server(b)):
            return a == b
        case let (.network(a), .network(b)):
            return a == b
        case let (.decoding(a), .decoding(b)):
            return a == b
        default:
            return false
        }
    }
}

public extension APIError {
    /// Shown for a 403 that is not hidden silently (optional functions are hidden, see the
    /// instance's Features list). Names no group and no pull request.
    static let missingPrivilegeMessage =
        "This account is not allowed to do this (403). Ask the Engelsystem administrators to give it the matching privilege."

    /// User-facing English message for this error, shared by every feature that
    /// surfaces `APIError` to the UI (Instance Setup, Shifts, News, Profile).
    var userMessage: String {
        switch self {
        case .unauthorized:
            return "API key is invalid or has expired."
        case .forbidden:
            return Self.missingPrivilegeMessage
        case .notFound:
            return "This resource could not be found (404)."
        case .invalidBaseURL:
            return "Please enter a valid server URL."
        case let .server(statusCode):
            return "Server responded with error \(statusCode)."
        case let .network(description):
            return "Connection failed: \(description)"
        case let .decoding(description):
            return "Could not read the API response: \(description)"
        }
    }
}

extension APIError {
    init(_ error: Error) {
        if let apiError = error as? APIError {
            self = apiError
            return
        }
        guard let errorResponse = error as? ErrorResponse else {
            self = .network(error.localizedDescription)
            return
        }
        switch errorResponse {
        case let .error(statusCode, _, _, underlying):
            switch statusCode {
            case 401:
                self = .unauthorized
            case 403:
                self = .forbidden
            case 404:
                self = .notFound
            default:
                if let decodingError = underlying as? DecodingError {
                    self = .decoding(Self.describe(decodingError))
                } else {
                    self = .server(statusCode: statusCode)
                }
            }
        }
    }
}

extension APIError {
    /// Where a response did not match the schema — the coding path and kind only, never the data
    /// itself, so it is safe to log and show.
    static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            let text = context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
            return text.isEmpty ? "the response" : String(text.drop(while: { $0 == "." }))
        }
        switch error {
        case let .keyNotFound(key, context):
            return "missing field “\(key.stringValue)” at \(path(context))"
        case let .typeMismatch(type, context):
            return "wrong type at \(path(context)) (expected \(type))"
        case let .valueNotFound(type, context):
            return "empty value at \(path(context)) (expected \(type))"
        default:
            return "invalid data (\(error.localizedDescription))"
        }
    }
}
