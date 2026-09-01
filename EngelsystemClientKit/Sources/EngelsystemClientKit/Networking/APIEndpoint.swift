import Foundation

/// Encapsulates the "{id}" path parameter of the Engelsystem API (an integer ID or the
/// string `self`), so callers outside the networking layer don't have to work with generated DTO types.
public enum UserReference {
    case me
    case id(Int)
}

extension UserReference {
    var parameter: UsersIdGetIdParameter {
        switch self {
        case .me: return .typeString("self")
        case let .id(id): return .typeInt(id)
        }
    }
}
