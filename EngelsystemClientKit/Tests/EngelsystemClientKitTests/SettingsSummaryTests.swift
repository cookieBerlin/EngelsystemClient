import Testing
@testable import EngelsystemClientKit

struct SettingsSummaryTests {
    @Test func instanceSummaryCountsActiveInstances() {
        #expect(SettingsSummary.instances(active: 0, total: 0) == "None")
        #expect(SettingsSummary.instances(active: 1, total: 3) == "1 of 3 active")
    }

    @Test func notificationSummaryListsSortedLeadTimes() {
        #expect(SettingsSummary.notifications(leadTimes: []) == "Off")
        #expect(SettingsSummary.notifications(leadTimes: [15]) == "15 min")
        #expect(SettingsSummary.notifications(leadTimes: [30, 15]) == "15, 30 min")
    }

    @Test func syncSummaryUsesTheIntervalTitle() {
        #expect(SettingsSummary.sync(pollingIntervalMinutes: PollingInterval.manual.rawValue) == PollingInterval.manual.title)
        #expect(SettingsSummary.sync(pollingIntervalMinutes: 30) == PollingInterval(minutes: 30).title)
        #expect(SettingsSummary.watchSync(onAppStart: true) == "On app start")
        #expect(SettingsSummary.watchSync(onAppStart: false) == "Manual")
    }

    @Test func diagnosticsSummaryAndVersion() {
        #expect(SettingsSummary.diagnostics(isEnabled: true) == "Logging on")
        #expect(SettingsSummary.diagnostics(isEnabled: false) == "Logging off")
        #expect(SettingsSummary.version(info: ["CFBundleShortVersionString": "0.1.0"]) == "0.1.0")
        #expect(SettingsSummary.version(info: nil) == "")
        #expect(SettingsSummary.version(info: ["CFBundleShortVersionString": 3]) == "")
    }
}
