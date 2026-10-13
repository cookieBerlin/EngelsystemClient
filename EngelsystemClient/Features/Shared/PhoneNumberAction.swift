import Foundation

/// Which kind of number a contact field holds (2026-10-13, user-requested): up to five
/// digits is an internal (DECT) short number, everything else is a normal phone number.
enum PhoneNumberKind: String, CaseIterable, Identifiable {
    case internalNumber
    case otherNumber

    var id: String { rawValue }

    var title: String {
        switch self {
        case .internalNumber: return "Internal Numbers"
        case .otherNumber: return "Other Numbers"
        }
    }
}

/// A contact number cleaned for dialing. Fails for empty values and anything that is not
/// plain digits with an optional leading `+` (such values can only be copied).
struct PhoneNumber: Equatable {
    static let maxInternalDigits = 5

    let dialable: String
    let kind: PhoneNumberKind

    init?(_ raw: String) {
        let separators = CharacterSet(charactersIn: " -().\u{00A0}/")
        let cleaned = String(String.UnicodeScalarView(raw.unicodeScalars.filter { !separators.contains($0) }))
        let hasPlus = cleaned.hasPrefix("+")
        let digits = hasPlus ? String(cleaned.dropFirst()) : cleaned
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        dialable = cleaned
        kind = !hasPlus && digits.count <= Self.maxInternalDigits ? .internalNumber : .otherNumber
    }
}

/// The app a number is handed to.
enum CallApp: String, CaseIterable, Identifiable, Codable {
    /// iOS decides: `sip:` for internal numbers, `tel:` for other numbers.
    case system
    case acrobitsSoftphone
    case groundwire
    case cloudSoftphone
    case custom
    /// No link at all, the number can only be copied.
    case copyOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System Default"
        case .acrobitsSoftphone: return "Acrobits Softphone"
        case .groundwire: return "Groundwire"
        case .cloudSoftphone: return "Cloud Softphone"
        case .custom: return "Custom Scheme"
        case .copyOnly: return "Copy Only"
        }
    }

    /// The app's own URL scheme (Acrobits "Call URIs": asoftphone / groundwire / cloudsip).
    var scheme: String? {
        switch self {
        case .acrobitsSoftphone: return "asoftphone"
        case .groundwire: return "groundwire"
        case .cloudSoftphone: return "cloudsip"
        case .system, .custom, .copyOnly: return nil
        }
    }
}

/// What an Acrobits app does with the number (`dialAction`; without one the app only
/// opens with the number filled in and the user taps "call").
enum CallAction: String, CaseIterable, Identifiable, Codable {
    case prefill
    case videoCall
    case text
    case gsmCall

    var id: String { rawValue }

    var title: String {
        switch self {
        case .prefill: return "Prepare Number"
        case .videoCall: return "Video Call"
        case .text: return "Text Message"
        case .gsmCall: return "Cellular Call"
        }
    }

    var dialAction: String? { self == .prefill ? nil : rawValue }
}

/// How numbers of one kind are opened; stored per device, one value per `PhoneNumberKind`.
struct CallPreference: Codable, Equatable {
    var app: CallApp = .system
    var action: CallAction = .prefill
    var customTemplate: String = "sip:{number}"

    static let numberPlaceholder = "{number}"
    static let blockedSchemes = ["http", "https", "file", "javascript", "data", "ftp"]

    static func userDefaultsKey(for kind: PhoneNumberKind) -> String { "callPreference.\(kind.rawValue)" }

    /// The stored value, or the default (system) for an empty or damaged value.
    static func decode(raw: String) -> CallPreference {
        guard let data = raw.data(using: .utf8),
              let value = try? JSONDecoder().decode(CallPreference.self, from: data) else { return CallPreference() }
        return value
    }

    var encoded: String {
        // `CallPreference` only holds strings, so encoding cannot fail.
        String(decoding: (try? JSONEncoder().encode(self)) ?? Data(), as: UTF8.self)
    }

    /// The link template this preference stands for; nil when numbers are only copied.
    func template(for kind: PhoneNumberKind) -> String? {
        switch app {
        case .copyOnly: return nil
        case .custom: return customTemplate
        case .system: return (kind == .internalNumber ? "sip:" : "tel:") + Self.numberPlaceholder
        case .acrobitsSoftphone, .groundwire, .cloudSoftphone:
            let base = (app.scheme ?? "") + ":" + Self.numberPlaceholder
            return action.dialAction.map { base + "?dialAction=" + $0 } ?? base
        }
    }

    /// The link to open for `number`, or nil (copy only, or an unusable custom template).
    func url(for number: PhoneNumber) -> URL? {
        guard let template = template(for: number.kind),
              app != .custom || Self.isValidTemplate(template) else { return nil }
        return URL(string: template.replacingOccurrences(of: Self.numberPlaceholder, with: number.dialable))
    }

    /// A custom template needs the placeholder and a scheme that is not a web or file address.
    static func isValidTemplate(_ template: String) -> Bool {
        guard template.contains(numberPlaceholder),
              let url = URL(string: template.replacingOccurrences(of: numberPlaceholder, with: "1000")),
              let scheme = url.scheme?.lowercased() else { return false }
        return !blockedSchemes.contains(scheme)
    }

    /// The preference after choosing `newApp`. Switching from a preset to "Custom" starts
    /// the custom template from that preset, so it can be adjusted.
    func switching(to newApp: CallApp, kind: PhoneNumberKind) -> CallPreference {
        var result = self
        if newApp == .custom, app != .custom, let current = template(for: kind) {
            result.customTemplate = current
        }
        result.app = newApp
        return result
    }
}
