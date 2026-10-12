import Foundation
import Testing
@testable import EngelsystemClientKit

private final class FakeWatchSession: WatchSessionControlling {
    var isSupported = true
    var isActivated = true
    var isPaired = true
    var isWatchAppInstalled = true
    var activations = 0
    var sent: [TimeInterval] = []
    var failure: Error?
    struct Failure: Error {}

    func activate() { activations += 1 }
    func sendShiftsChanged(at timestamp: TimeInterval) throws {
        if let failure { throw failure }
        sent.append(timestamp)
    }
}

struct WatchConnectivityBridgeLogicTests {
    @Test func activatesOnlyASupportedSession() {
        let supported = FakeWatchSession()
        WatchConnectivityBridge.activate(using: supported)
        #expect(supported.activations == 1)

        let unsupported = FakeWatchSession()
        unsupported.isSupported = false
        WatchConnectivityBridge.activate(using: unsupported)
        #expect(unsupported.activations == 0)
    }

    @Test func aReadySessionReceivesTheTimestampNudge() {
        let session = FakeWatchSession()
        WatchConnectivityBridge.notifyShiftsChanged(using: session, now: Date(timeIntervalSinceReferenceDate: 1234))
        #expect(session.sent == [1234])
    }

    @Test func nothingIsSentUnlessActivatedPairedAndInstalled() {
        let mutations: [(FakeWatchSession) -> Void] = [
            { $0.isActivated = false }, { $0.isPaired = false }, { $0.isWatchAppInstalled = false },
        ]
        for mutate in mutations {
            let session = FakeWatchSession()
            mutate(session)
            WatchConnectivityBridge.notifyShiftsChanged(using: session, now: Date())
            #expect(session.sent.isEmpty)
        }
    }

    @Test func anUnsupportedSessionIsIgnoredEntirely() {
        let session = FakeWatchSession()
        session.isSupported = false
        WatchConnectivityBridge.notifyShiftsChanged(using: session, now: Date())
        #expect(session.sent.isEmpty)
    }

    @Test func aFailingSendIsLoggedNotThrown() {
        let session = FakeWatchSession()
        session.failure = FakeWatchSession.Failure()
        WatchConnectivityBridge.notifyShiftsChanged(using: session, now: Date())
        #expect(session.sent.isEmpty)
    }

    @Test func theNoArgumentEntryPointsAreSafeOnThisPlatform() {
        WatchConnectivityBridge.activate()
        WatchConnectivityBridge.notifyShiftsChanged()
    }
}
