import Foundation
import Testing
@testable import EngelsystemClientKit

@MainActor
struct SyncRunModelTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let home = UUID()
    let congress = UUID()

    private func model(_ planned: [(UUID, String)]) -> SyncRunModel {
        let model = SyncRunModel()
        model.apply(.planned(planned.map { SyncPlannedInstance(id: $0.0, name: $0.1, totalSteps: 5) }), now: now)
        return model
    }

    @Test func plannedInstancesWaitWithAnEmptyLine() {
        let model = model([(home, "Home"), (congress, "Congress")])
        #expect(model.rows.map(\.status) == [.waiting, .waiting])
        #expect(model.rows[0].fraction == 0)
        #expect(model.text(for: model.rows[1], now: now) == "Congress · waiting")
        #expect(model.stepCountText(for: model.rows[1]) == nil)
        #expect(model.systemImage(for: model.rows[1], now: now) == "circle.dotted")
        #expect(model.accessibilityText(for: model.rows[1], now: now) == "Congress · waiting")
    }

    @Test func stepsAdvanceTheLineAndTheTextNamesTheArea() {
        let model = model([(home, "Home"), (congress, "Congress")])
        model.apply(.instanceStarted(id: home), now: now)
        model.apply(.stepStarted(id: home, area: "Shifts"), now: now)
        model.apply(.stepFinished(id: home, area: "Shifts"), now: now)
        model.apply(.stepStarted(id: home, area: "News"), now: now)
        let row = model.rows[0]
        #expect(row.status == .running)
        #expect(row.fraction == 0.2)
        #expect(model.text(for: row, now: now) == "Home · News")
        #expect(model.stepCountText(for: row) == "1/5")
        #expect(model.accessibilityText(for: row, now: now) == "Home · News, step 1 of 5")
        #expect(model.systemImage(for: row, now: now) == "arrow.triangle.2.circlepath")
    }

    @Test func aSingleInstanceHasNoNameInTheText() {
        let model = model([(home, "Home")])
        #expect(!model.showsNames)
        model.apply(.instanceStarted(id: home), now: now)
        #expect(model.text(for: model.rows[0], now: now) == "Starting")
        model.apply(.stepStarted(id: home, area: "Shifts"), now: now)
        #expect(model.text(for: model.rows[0], now: now) == "Shifts")
    }

    @Test func aStepSlowerThanThirtySecondsIsNotResponding() {
        let model = model([(home, "Home"), (congress, "Congress")])
        model.apply(.instanceStarted(id: home), now: now)
        model.apply(.stepStarted(id: home, area: "Shifts"), now: now)
        let row = model.rows[0]
        #expect(!model.isSlow(row, now: now.addingTimeInterval(29)))
        #expect(model.isSlow(row, now: now.addingTimeInterval(30)))
        #expect(model.text(for: row, now: now.addingTimeInterval(31)) == "Home · not responding")
        #expect(model.systemImage(for: row, now: now.addingTimeInterval(31)) == "exclamationmark.triangle.fill")
        #expect(!model.isSlow(model.rows[1], now: now.addingTimeInterval(99))) // waiting rows are never "slow"
    }

    @Test func finishedRowsShowTheirOutcome() {
        let model = model([(home, "Home"), (congress, "Congress")])
        model.apply(.instanceStarted(id: home), now: now)
        model.apply(.instanceFinished(id: home, outcome: .succeeded), now: now)
        model.apply(.instanceFinished(id: congress, outcome: .timedOut), now: now)
        #expect(model.rows[0].fraction == 1)
        #expect(model.text(for: model.rows[0], now: now) == "Home · done")
        #expect(model.systemImage(for: model.rows[0], now: now) == "checkmark.circle.fill")
        #expect(model.text(for: model.rows[1], now: now) == "Congress · timed out")
        #expect(model.systemImage(for: model.rows[1], now: now) == "exclamationmark.triangle.fill")
        #expect(model.problemSummary == "Partially failed: Congress (timed out)")
    }

    @Test func skippedAndFailedRowsAreDescribed() {
        let model = model([(home, "Home"), (congress, "Congress")])
        model.apply(.instanceFinished(id: home, outcome: .skipped), now: now)
        model.apply(.instanceFinished(id: congress, outcome: .failed), now: now)
        #expect(model.text(for: model.rows[0], now: now) == "Home · skipped")
        #expect(model.systemImage(for: model.rows[0], now: now) == "forward.circle")
        #expect(model.text(for: model.rows[1], now: now) == "Congress · failed")
        #expect(model.problemSummary == "Partially failed: Congress (failed)")
    }

    @Test func aCleanRunHasNoProblemSummaryAndUnknownIDsAreIgnored() {
        let model = model([(home, "Home")])
        model.apply(.instanceFinished(id: home, outcome: .succeeded), now: now)
        model.apply(.stepStarted(id: UUID(), area: "News"), now: now)
        #expect(model.problemSummary == nil)
        #expect(model.rows.count == 1)
        let single = self.model([(home, "Home")])
        single.apply(.instanceFinished(id: home, outcome: .failed), now: now)
        #expect(single.problemSummary == "Partially failed: failed")
    }

    @Test func resetClearsTheRows() {
        let model = model([(home, "Home")])
        model.reset()
        #expect(model.rows.isEmpty)
        #expect(!model.showsNames)
    }

    @Test func aRowWithoutStepsHasNoFraction() {
        #expect(SyncRunModel.Row(id: home, name: "Home", totalSteps: 0).fraction == 0)
    }
}

@MainActor
struct SyncControlTests {
    @Test func aWaitingInstanceCanBeSkippedOnce() {
        let control = SyncControl()
        let id = UUID()
        control.skip(id)
        #expect(control.consumeSkip(id))
        #expect(!control.consumeSkip(id))
    }

    @Test func progressMadeIsIgnoredWithoutARunningInstance() {
        let control = SyncControl()
        let id = UUID()
        control.progressMade(id)
        let result = control.end(id)
        #expect(!result.timedOut && !result.skipped)
    }

    @Test func theWatchdogCancelsOnlyTheInstanceWithoutProgress() async {
        let control = SyncControl(stepTimeout: 0.05)
        let stuck = UUID()
        let busy = UUID()
        let stuckWorker = Task { @MainActor in
            while !Task.isCancelled { await Task.yield() }
        }
        let busyWorker = Task { @MainActor in
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(20))
                control.progressMade(busy)
            }
        }
        control.begin(stuck, worker: stuckWorker)
        control.begin(busy, worker: busyWorker)
        await stuckWorker.value
        await busyWorker.value
        #expect(control.end(stuck).timedOut)
        #expect(!control.end(busy).timedOut)
        #expect(!busyWorker.isCancelled)
    }

    @Test func skippingTheRunningInstanceCancelsItAndIsReported() async {
        let control = SyncControl()
        let id = UUID()
        let other = UUID()
        let worker = Task { @MainActor in
            while !Task.isCancelled { await Task.yield() }
        }
        let otherWorker = Task { @MainActor in }
        control.begin(id, worker: worker)
        control.begin(other, worker: otherWorker)
        control.skip(id)
        await worker.value
        let result = control.end(id)
        #expect(result.skipped)
        #expect(!result.timedOut)
        #expect(!control.end(other).skipped)
    }
}

struct ParallelSyncSettingTests {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "ParallelSync-\(UUID().uuidString)")! }

    @Test func valuesStayInsideTheRange() {
        #expect(ParallelSyncSetting.clamp(-3) == 0)
        #expect(ParallelSyncSetting.clamp(4) == 4)
        #expect(ParallelSyncSetting.clamp(99) == 10)
    }

    @Test func unsetMeansUnlimitedAndStoredValuesAreClamped() {
        let defaults = defaults()
        #expect(ParallelSyncSetting.stored(in: defaults) == 0)
        defaults.set(3, forKey: ParallelSyncSetting.userDefaultsKey)
        #expect(ParallelSyncSetting.stored(in: defaults) == 3)
        defaults.set(-1, forKey: ParallelSyncSetting.userDefaultsKey)
        #expect(ParallelSyncSetting.stored(in: defaults) == 0)
        defaults.set(50, forKey: ParallelSyncSetting.userDefaultsKey)
        #expect(ParallelSyncSetting.stored(in: defaults) == 10)
    }

    @Test func titlesNameTheLimit() {
        #expect(ParallelSyncSetting.title(for: 0) == "Unlimited")
        #expect(ParallelSyncSetting.title(for: 1) == "1 at a time")
        #expect(ParallelSyncSetting.title(for: 3) == "3 at a time")
        #expect(ParallelSyncSetting.title(for: 40) == "10 at a time")
    }
}
