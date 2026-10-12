import Foundation

extension UsersIdGetIdParameter {
    /// The user-scoped endpoints are always addressed as the signed-in user (`self`).
    static let me = UsersIdGetIdParameter.typeString("self")
}

/// `UsersIdGetIdParameter` (generated, `Generated/Models/UsersIdGetIdParameter.swift`) is a
/// plain `enum` with associated values, not `RawRepresentable` — so
/// `APIHelper.mapValueToPathItem` (also generated) falls through its `RawRepresentable`
/// check and returns the enum itself, which then gets string-interpolated as-is into the
/// request path. Without this conformance that produced `"typeInt(2)"`/
/// `"typeString(\"self\")"` as the literal `{id}` path segment (e.g.
/// `/users/typeInt(2)/shifts`) instead of `"2"`/`"self"` — a malformed URL that 404s
/// regardless of the actual user ID. `CustomStringConvertible`'s `description` **is**
/// picked up by that interpolation (`"\(value)"` where `value: Any` dynamically conforms),
/// so this fixes it without touching `Generated/`. Root-caused 2026-09-17: this is what the
/// 2026-09-05 "server rejects `self`" diagnosis actually was — the server was never sent
/// `self` or a real numeric ID at all, on *any* user-scoped endpoint (shifts, worklogs,
/// profile, angel types).
extension UsersIdGetIdParameter: CustomStringConvertible {
    public var description: String {
        switch self {
        case .typeInt(let value): return String(value)
        case .typeString(let value): return value
        }
    }
}
