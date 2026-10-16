import Foundation
import Testing
@testable import EngelsystemClientKit

private final class FakeWatchSession: WatchSessionControlling {
    var isSupported = true
    var isActivated = true
    var isPaired = true
    var isWatchAppInstalled = true
    var isReachable = false
    var activations = 0
    var contexts: [[String: Any]] = []
    var messages: [[String: Any]] = []
    var failure: Error?
    struct Failure: Error {}

    func activate() { activations += 1 }
    func updateContext(_ context: [String: Any]) throws {
        if let failure { throw failure }
        contexts.append(context)
    }
    func sendMessage(_ message: [String: Any]) { messages.append(message) }
}

private func freshState() -> WatchContextState {
    WatchContextState(defaults: UserDefaults(suiteName: "WatchContextState-\(UUID().uuidString)")!)
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
        WatchConnectivityBridge.notifyShiftsChanged(using: session, now: Date(timeIntervalSinceReferenceDate: 1234), state: freshState())
        #expect(session.contexts.last?["shiftsChangedAt"] as? Double == 1234)
    }

    @Test func nothingIsSentUnlessActivatedPairedAndInstalled() {
        let mutations: [(FakeWatchSession) -> Void] = [
            { $0.isActivated = false }, { $0.isPaired = false }, { $0.isWatchAppInstalled = false },
        ]
        for mutate in mutations {
            let session = FakeWatchSession()
            mutate(session)
            WatchConnectivityBridge.notifyShiftsChanged(using: session, now: Date(), state: freshState())
            #expect(session.contexts.isEmpty)
        }
    }

    @Test func anUnsupportedSessionIsIgnoredEntirely() {
        let session = FakeWatchSession()
        session.isSupported = false
        WatchConnectivityBridge.notifyShiftsChanged(using: session, now: Date(), state: freshState())
        #expect(session.contexts.isEmpty)
    }

    @Test func aFailingSendIsLoggedNotThrown() {
        let session = FakeWatchSession()
        session.failure = FakeWatchSession.Failure()
        WatchConnectivityBridge.notifyShiftsChanged(using: session, now: Date(), state: freshState())
        #expect(session.contexts.isEmpty)
    }

    @Test func theNoArgumentEntryPointsAreSafeOnThisPlatform() {
        WatchConnectivityBridge.activate()
        WatchConnectivityBridge.notifyShiftsChanged()
        #expect(WatchConnectivityBridge.requestWatchLog() == .unavailable)
        #expect(!WatchConnectivityBridge.setWatchLogging(true))
    }

    @Test func aLogRequestGoesLiveWhenTheWatchIsReachableAndIsAlwaysKept() {
        let state = freshState()
        let session = FakeWatchSession()
        session.isReachable = true
        let outcome = WatchConnectivityBridge.requestWatchLog(using: session, id: "A", state: state)
        #expect(outcome == .sentLive)
        #expect(session.messages.count == 1 && session.messages[0][WatchLogKeys.requestLog] as? String == "A")
        #expect(session.contexts.last?[WatchLogKeys.logRequestID] as? String == "A")
    }

    @Test func aLogRequestWaitsForAWatchThatIsNotReachable() {
        let session = FakeWatchSession()
        #expect(WatchConnectivityBridge.requestWatchLog(using: session, id: "B", state: freshState()) == .queued)
        #expect(session.messages.isEmpty)
        #expect(session.contexts.last?[WatchLogKeys.logRequestID] as? String == "B")
    }

    @Test func aLogRequestNeedsAReadyWatchAndAWorkingSession() {
        let notPaired = FakeWatchSession()
        notPaired.isPaired = false
        #expect(WatchConnectivityBridge.requestWatchLog(using: notPaired, state: freshState()) == .unavailable)
        let failing = FakeWatchSession()
        failing.failure = FakeWatchSession.Failure()
        #expect(WatchConnectivityBridge.requestWatchLog(using: failing, state: freshState()) == .unavailable)
        #expect(failing.messages.isEmpty)
        // A generated id is used when none is given.
        let session = FakeWatchSession()
        _ = WatchConnectivityBridge.requestWatchLog(using: session, state: freshState())
        #expect((session.contexts.last?[WatchLogKeys.logRequestID] as? String)?.isEmpty == false)
    }

    @Test func theLoggingSwitchTravelsWithTheOtherPartsOfTheContext() {
        let state = freshState()
        let session = FakeWatchSession()
        WatchConnectivityBridge.notifyShiftsChanged(using: session, now: Date(timeIntervalSinceReferenceDate: 10), state: state)
        #expect(WatchConnectivityBridge.setWatchLogging(false, using: session, now: Date(timeIntervalSince1970: 500), state: state))
        let context = session.contexts.last
        #expect(context?[WatchLogKeys.loggingOn] as? Bool == false)
        #expect(context?[WatchLogKeys.loggingChangedAt] as? Double == 500)
        #expect(context?["shiftsChangedAt"] as? Double == 10) // not lost by the later update

        let failing = FakeWatchSession()
        failing.failure = FakeWatchSession.Failure()
        #expect(!WatchConnectivityBridge.setWatchLogging(true, using: failing, state: freshState()))
        failing.isPaired = false
        #expect(!WatchConnectivityBridge.setWatchLogging(true, using: failing, state: freshState()))
    }
}
