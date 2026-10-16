import Foundation
import EngelsystemClientKit

/// Backs the "Logs received from Apple Watch" part of the Diagnostics page (2026-10-16): the logs the Watch sent, the
/// request for a new one and the remote switch for the Watch's logging. The Watch does the sending; this side stores,
/// lists and shares. The system session is injected so the decisions are tested without a Watch.
@Observable
@MainActor
final class WatchLogsViewModel {
    private(set) var items: [ReceivedWatchLogs.Item] = []
    private(set) var report: WatchLogReport?
    private(set) var desiredSwitch: LoggingSwitch?
    /// What the page says below "Request Log": the outcome of the last request.
    private(set) var requestStatus: String?

    private let logs: ReceivedWatchLogs
    private let inbox: WatchLogInbox
    private let requestLog: () -> WatchLogRequestOutcome
    private let setLogging: (Bool) -> Bool
    private let desired: () -> LoggingSwitch?

    init(
        logs: ReceivedWatchLogs = ReceivedWatchLogs(),
        inbox: WatchLogInbox = WatchLogInbox(),
        requestLog: @escaping () -> WatchLogRequestOutcome = { WatchConnectivityBridge.requestWatchLog() },
        setLogging: @escaping (Bool) -> Bool = { WatchConnectivityBridge.setWatchLogging($0) },
        desired: @escaping () -> LoggingSwitch? = { WatchConnectivityBridge.desiredWatchLogging() }
    ) {
        self.logs = logs
        self.inbox = inbox
        self.requestLog = requestLog
        self.setLogging = setLogging
        self.desired = desired
        refresh()
    }

    /// Reads the folder, the Watch's last report and the iPhone's last wish again.
    func refresh() {
        items = logs.list()
        report = inbox.lastReport
        desiredSwitch = desired()
    }

    /// What the "Log on Apple Watch" switch shows, and whether the Watch confirmed it.
    var loggingStatus: WatchLoggingStatus {
        WatchLoggingStatus(desired: desiredSwitch, report: report)
    }

    /// The text below the switch: confirmed state, "waiting", or nothing known yet.
    func loggingStatusText(now: Date = Date()) -> String {
        switch loggingStatus.kind {
        case .unknown:
            return "The Apple Watch has not reported yet."
        case .waiting:
            return "Waiting for Apple Watch"
        case let .reported(reportedAt):
            let age = reportedAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
            return (loggingStatus.isOn ? "On" : "Off") + " · reported " + age
        }
    }

    func setWatchLogging(_ isOn: Bool) {
        _ = setLogging(isOn)
        refresh()
    }

    func request() {
        switch requestLog() {
        case .sentLive:
            requestStatus = "Requested. Waiting for the Apple Watch to answer."
        case .queued:
            requestStatus = "Requested. The Apple Watch answers when its app runs."
        case .unavailable:
            requestStatus = "No paired Apple Watch with the app installed."
        }
    }

    func entries(of item: ReceivedWatchLogs.Item) -> [DebugLogEntry] {
        logs.entries(of: item)
    }

    func delete(_ item: ReceivedWatchLogs.Item) {
        logs.delete(item)
        refresh()
    }

    func deleteAll() {
        logs.deleteAll()
        refresh()
    }

    /// Every received log as files, for one share sheet.
    var shareURLs: [URL] { items.map(\.url) }
}
