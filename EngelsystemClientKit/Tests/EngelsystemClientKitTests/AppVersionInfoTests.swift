import Foundation
import Testing
@testable import EngelsystemClientKit

struct AppVersionInfoTests {
    @Test func displayStringShowsVersionBuildAndAKnownCommitHash() {
        let info: [String: Any] = ["CFBundleShortVersionString": "1.2", "CFBundleVersion": "34", "GitCommitHash": "abc1234"]
        #expect(AppVersionInfo.displayString(info: info) == "Version 1.2 (34) · abc1234")
    }

    @Test func missingValuesAndUnknownHashesAreOmitted() {
        #expect(AppVersionInfo.displayString(info: nil) == "Version ? (?)")
        #expect(AppVersionInfo.displayString(info: ["GitCommitHash": "unknown"]) == "Version ? (?)")
        #expect(AppVersionInfo.displayString(info: ["GitCommitHash": ""]) == "Version ? (?)")
        _ = AppVersionInfo.displayString
    }
}
