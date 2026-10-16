import Foundation

/// What `AppSyncCoordinator` tells while it syncs, per instance — the banner on the main page
/// builds its rows from these (`SyncRunModel`).
public enum SyncEvent: Equatable, Sendable {
    /// Every instance of the run, announced up front so the banner can list the waiting ones.
    case planned([SyncPlannedInstance])
    case instanceStarted(id: UUID)
    case stepStarted(id: UUID, area: String)
    case stepFinished(id: UUID, area: String)
    case instanceFinished(id: UUID, outcome: SyncInstanceOutcome)
}

public struct SyncPlannedInstance: Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let totalSteps: Int

    public init(id: UUID, name: String, totalSteps: Int) {
        self.id = id
        self.name = name
        self.totalSteps = totalSteps
    }
}

public enum SyncInstanceOutcome: Equatable, Sendable {
    case succeeded
    /// At least one area failed (a real error, not "not allowed"/"not offered").
    case failed
    /// No progress for `SyncControl.stepTimeout` seconds; the instance was cancelled.
    case timedOut
    /// The user skipped it.
    case skipped
}

/// Lets the user skip an instance and cancels one that stops making progress. Several instances can run
/// at the same time, each with its own worker task and no-progress timer.
@MainActor
public final class SyncControl {
    /// An instance that makes no progress for this long is cancelled.
    nonisolated public static let defaultStepTimeout: TimeInterval = 60

    private let stepTimeout: TimeInterval
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private var workers: [UUID: Task<Void, Never>] = [:]
    private var watchdogs: [UUID: Task<Void, Never>] = [:]
    private var timedOut: Set<UUID> = []
    private var skipRequests: Set<UUID> = []

    public init(
        stepTimeout: TimeInterval = SyncControl.defaultStepTimeout,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.stepTimeout = stepTimeout
        self.sleep = sleep
    }

    /// Skips an instance: a running one is cancelled, a waiting one is passed over when its turn comes.
    public func skip(_ id: UUID) {
        skipRequests.insert(id)
        workers[id]?.cancel()
    }

    /// Whether a waiting instance was skipped (and forgets the request).
    public func consumeSkip(_ id: UUID) -> Bool {
        skipRequests.remove(id) != nil
    }

    func begin(_ id: UUID, worker: Task<Void, Never>) {
        workers[id] = worker
        timedOut.remove(id)
        armWatchdog(id)
    }

    /// The instance made progress: its no-progress timer starts over.
    func progressMade(_ id: UUID) {
        guard workers[id] != nil else { return }
        armWatchdog(id)
    }

    /// Ends an instance and tells whether it was cancelled for lack of progress or skipped.
    func end(_ id: UUID) -> (timedOut: Bool, skipped: Bool) {
        watchdogs.removeValue(forKey: id)?.cancel()
        workers.removeValue(forKey: id)
        return (timedOut.remove(id) != nil, skipRequests.remove(id) != nil)
    }

    private func armWatchdog(_ id: UUID) {
        watchdogs[id]?.cancel()
        let sleep = self.sleep
        let timeout = stepTimeout
        watchdogs[id] = Task { @MainActor [weak self] in
            // A cancelled watchdog (progress was made, or the instance ended) must not fire.
            guard (try? await sleep(timeout)) != nil, !Task.isCancelled, let self else { return }
            timedOut.insert(id)
            workers[id]?.cancel()
        }
    }
}

/// The state of a run as the banner shows it: one row per instance with its steps, built from `SyncEvent`s.
@Observable
@MainActor
public final class SyncRunModel {
    public enum Status: Equatable, Sendable {
        case waiting, running, succeeded, failed, timedOut, skipped
    }

    public struct Row: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let name: String
        public let totalSteps: Int
        public var completedSteps = 0
        public var currentArea: String?
        public var status = Status.waiting
        /// When the current step began; the "not responding" warning counts from here.
        public var stepStartedAt: Date?

        /// 0…1 for the thin line under the row.
        public var fraction: Double {
            guard totalSteps > 0 else { return 0 }
            return status == .waiting ? 0 : min(Double(completedSteps) / Double(totalSteps), 1)
        }
    }

    /// A step that takes longer than this gets the "not responding" warning.
    public static let slowAfter: TimeInterval = 30

    public private(set) var rows: [Row] = []

    public init() {}

    /// Clears the rows (a run without instances, or the banner going away).
    public func reset() { rows = [] }

    public func apply(_ event: SyncEvent, now: Date = Date()) {
        switch event {
        case let .planned(instances):
            rows = instances.map { Row(id: $0.id, name: $0.name, totalSteps: $0.totalSteps) }
        case let .instanceStarted(id):
            update(id) { $0.status = .running }
        case let .stepStarted(id, area):
            update(id) {
                $0.currentArea = area
                $0.stepStartedAt = now
            }
        case let .stepFinished(id, _):
            update(id) { $0.completedSteps += 1 }
        case let .instanceFinished(id, outcome):
            update(id) {
                $0.status = Self.status(for: outcome)
                $0.currentArea = nil
                $0.stepStartedAt = nil
                if outcome == .succeeded { $0.completedSteps = $0.totalSteps }
            }
        }
    }

    public func isSlow(_ row: Row, now: Date) -> Bool {
        guard row.status == .running, let started = row.stepStartedAt else { return false }
        return now.timeIntervalSince(started) >= Self.slowAfter
    }

    /// Names lead the text only when more than one instance is syncing.
    public var showsNames: Bool { rows.count > 1 }

    /// Rows that ended badly, for the message that stays a few seconds after the run.
    public var problemSummary: String? {
        let problems = rows.filter { [.failed, .timedOut].contains($0.status) }
        guard !problems.isEmpty else { return nil }
        let list = problems.map { row in
            showsNames ? "\(row.name) (\(Self.reason(row.status)))" : Self.reason(row.status)
        }
        return "Partially failed: " + list.joined(separator: ", ")
    }

    /// The row's line: "Congress · News", "Test · waiting", "Home · not responding", "Home · timed out".
    public func text(for row: Row, now: Date) -> String {
        let detail: String
        switch row.status {
        case .waiting: detail = "waiting"
        case .running: detail = isSlow(row, now: now) ? "not responding" : (row.currentArea ?? "starting")
        case .succeeded: detail = "done"
        case .failed: detail = "failed"
        case .timedOut: detail = "timed out"
        case .skipped: detail = "skipped"
        }
        return showsNames ? "\(row.name) · \(detail)" : detail.prefix(1).uppercased() + detail.dropFirst()
    }

    /// "2/5" for a running or finished row.
    public func stepCountText(for row: Row) -> String? {
        row.status == .waiting ? nil : "\(row.completedSteps)/\(row.totalSteps)"
    }

    public func systemImage(for row: Row, now: Date) -> String {
        switch row.status {
        case .waiting: return "circle.dotted"
        case .running: return isSlow(row, now: now) ? "exclamationmark.triangle.fill" : "arrow.triangle.2.circlepath"
        case .succeeded: return "checkmark.circle.fill"
        case .failed, .timedOut: return "exclamationmark.triangle.fill"
        case .skipped: return "forward.circle"
        }
    }

    public func accessibilityText(for row: Row, now: Date) -> String {
        let text = text(for: row, now: now)
        return row.status == .waiting ? text : "\(text), step \(row.completedSteps) of \(row.totalSteps)"
    }

    private func update(_ id: UUID, _ change: (inout Row) -> Void) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        change(&rows[index])
    }

    private static func status(for outcome: SyncInstanceOutcome) -> Status {
        switch outcome {
        case .succeeded: return .succeeded
        case .failed: return .failed
        case .timedOut: return .timedOut
        case .skipped: return .skipped
        }
    }

    private static func reason(_ status: Status) -> String {
        status == .timedOut ? "timed out" : "failed"
    }
}
