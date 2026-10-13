import Foundation
import Testing
@testable import EngelsystemClient

struct PhoneNumberActionTests {
    @Test func upToFiveDigitsIsInternalEverythingElseIsNormal() {
        #expect(PhoneNumber("1000")?.kind == .internalNumber)
        #expect(PhoneNumber("123")?.kind == .internalNumber)
        #expect(PhoneNumber("12345")?.kind == .internalNumber)
        #expect(PhoneNumber("123456")?.kind == .otherNumber)
        #expect(PhoneNumber("+4915112345678")?.kind == .otherNumber)
        #expect(PhoneNumber("+1234")?.kind == .otherNumber)
    }

    @Test func separatorsAreRemovedAndNonNumbersRejected() {
        #expect(PhoneNumber("+49 (30) 123-4567")?.dialable == "+49301234567")
        #expect(PhoneNumber(" 10 00 ")?.dialable == "1000")
        #expect(PhoneNumber("")?.dialable == nil)
        #expect(PhoneNumber("+") == nil)
        #expect(PhoneNumber("12ab") == nil)
        #expect(PhoneNumber("angel") == nil)
        #expect(PhoneNumber("١٢٣") == nil)
    }

    @Test func systemDefaultUsesSipForInternalAndTelForOtherNumbers() throws {
        let preference = CallPreference()
        #expect(try preference.url(for: #require(PhoneNumber("1000")))?.absoluteString == "sip:1000")
        #expect(try preference.url(for: #require(PhoneNumber("+49 30 123456")))?.absoluteString == "tel:+4930123456")
    }

    @Test func acrobitsPresetsUseTheirSchemeAndAction() throws {
        let internalNumber = try #require(PhoneNumber("1000"))
        let other = try #require(PhoneNumber("+4930123456"))
        var preference = CallPreference(app: .acrobitsSoftphone)
        #expect(preference.url(for: internalNumber)?.absoluteString == "asoftphone:1000")
        preference.app = .groundwire
        preference.action = .gsmCall
        #expect(preference.url(for: other)?.absoluteString == "groundwire:+4930123456?dialAction=gsmCall")
        preference.app = .cloudSoftphone
        preference.action = .videoCall
        #expect(preference.url(for: internalNumber)?.absoluteString == "cloudsip:1000?dialAction=videoCall")
        preference.action = .text
        #expect(preference.url(for: internalNumber)?.absoluteString == "cloudsip:1000?dialAction=text")
        #expect(CallAction.allCases.map(\.title).count == 4)
        #expect(CallApp.allCases.map(\.title).count == 6)
    }

    @Test func copyOnlyHasNoLink() throws {
        let preference = CallPreference(app: .copyOnly)
        #expect(try preference.url(for: #require(PhoneNumber("1000"))) == nil)
        #expect(preference.template(for: .internalNumber) == nil)
    }

    @Test func customTemplatesAreValidatedAndFilled() throws {
        let number = try #require(PhoneNumber("1000"))
        var preference = CallPreference(app: .custom, customTemplate: "myphone://dial/{number}")
        #expect(preference.url(for: number)?.absoluteString == "myphone://dial/1000")
        preference.customTemplate = "myphone://dial/"
        #expect(preference.url(for: number) == nil)
        preference.customTemplate = "https://example.org/{number}"
        #expect(preference.url(for: number) == nil)
        preference.customTemplate = "not a url {number}"
        #expect(preference.url(for: number) == nil)
        #expect(CallPreference.isValidTemplate("sip:{number}"))
        #expect(!CallPreference.isValidTemplate("JAVASCRIPT:{number}"))
    }

    @Test func switchingToCustomKeepsTheLastPreset() {
        var preference = CallPreference(app: .groundwire, action: .text)
        preference = preference.switching(to: .custom, kind: .internalNumber)
        #expect(preference.app == .custom)
        #expect(preference.customTemplate == "groundwire:{number}?dialAction=text")
        // Switching between presets and from custom to a preset keeps the custom template.
        let back = preference.switching(to: .system, kind: .otherNumber)
        #expect(back.app == .system)
        #expect(back.customTemplate == "groundwire:{number}?dialAction=text")
        #expect(back.switching(to: .custom, kind: .otherNumber).customTemplate == "tel:{number}")
        // Custom stays itself; copy-only has no template to carry over.
        #expect(preference.switching(to: .custom, kind: .internalNumber) == preference)
        let copy = CallPreference(app: .copyOnly, customTemplate: "x:{number}")
        #expect(copy.switching(to: .custom, kind: .internalNumber).customTemplate == "x:{number}")
    }

    @Test func storedPreferencesRoundTripAndFallBackToTheDefault() {
        let stored = CallPreference(app: .groundwire, action: .gsmCall, customTemplate: "a:{number}")
        #expect(CallPreference.decode(raw: stored.encoded) == stored)
        #expect(CallPreference.decode(raw: "") == CallPreference())
        #expect(CallPreference.decode(raw: "{broken") == CallPreference())
        #expect(CallPreference.decode(raw: "bogus\ngsmCall\nx:{number}")
            == CallPreference(app: .system, action: .gsmCall, customTemplate: "x:{number}"))
        #expect(CallPreference.decode(raw: "groundwire\nbogus\nx:{number}")
            == CallPreference(app: .groundwire, action: .prefill, customTemplate: "x:{number}"))
        #expect(CallApp.allCases.map(\.id) == CallApp.allCases.map(\.rawValue))
        #expect(CallAction.allCases.map(\.id) == CallAction.allCases.map(\.rawValue))
        #expect(CallPreference.userDefaultsKey(for: .internalNumber) != CallPreference.userDefaultsKey(for: .otherNumber))
        #expect(PhoneNumberKind.allCases.map(\.title) == ["Internal Numbers", "Other Numbers"])
        #expect(Set(PhoneNumberKind.allCases.map(\.id)).count == 2)
        #expect(CallAction.prefill.dialAction == nil)
        #expect(CallApp.system.scheme == nil)
    }
}
