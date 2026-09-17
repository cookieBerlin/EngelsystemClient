import Foundation
import Testing
@testable import EngelsystemClientKit

struct CloudSyncStatusTests {
    @Test func displayTextIsHumanReadableForEveryCase() {
        #expect(CloudSyncStatus.checking.displayText == "Checking iCloud Sync…")
        #expect(CloudSyncStatus.active.displayText == "iCloud Sync: Active")
        #expect(CloudSyncStatus.noAccount.displayText == "iCloud Sync: No iCloud Account")
        #expect(CloudSyncStatus.restricted.displayText == "iCloud Sync: Restricted")
        #expect(CloudSyncStatus.temporarilyUnavailable.displayText == "iCloud Sync: Temporarily Unavailable")
        #expect(CloudSyncStatus.unknown.displayText == "iCloud Sync: Unknown")
        #expect(CloudSyncStatus.error("offline").displayText == "iCloud Sync: Error (offline)")
    }

    // `current(containerIdentifier:)` itself (the real `CKContainer.accountStatus()`
    // call) is deliberately not exercised here: `CKContainer` requires a codesigned app
    // bundle with the container identifier actually declared in its
    // icloud-container-identifiers entitlement — a bare `swift test` binary has neither,
    // and confirmed hands-on that calling it (even with a bogus identifier, to check
    // for a graceful error rather than a crash) crashes the test process outright
    // rather than throwing. Real coverage for this path is the manual Watch/iPhone
    // verification this type was built for, not a unit test.
}
