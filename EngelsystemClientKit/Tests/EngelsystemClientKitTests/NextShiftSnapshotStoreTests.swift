import Foundation
import Testing
@testable import EngelsystemClientKit

@Test func nextShiftSnapshotStoreRoundTripsAndClears() {
    // A plain (non-App-Group) suite name still works for UserDefaults(suiteName:) in a
    // test process, so this exercises the same save/load logic without needing the real
    // App Group entitlement.
    let store = NextShiftSnapshotStore(appGroupID: "de.engelsystem.tests.\(UUID().uuidString)")

    #expect(store.load() == nil)

    let snapshot = NextShiftSnapshot(
        title: "Info Desk Shift",
        startsAt: Date(timeIntervalSince1970: 1_700_000_000),
        endsAt: Date(timeIntervalSince1970: 1_700_010_800),
        locationName: "Heaven"
    )
    store.save(snapshot)
    #expect(store.load() == snapshot)

    store.save(nil)
    #expect(store.load() == nil)
}
