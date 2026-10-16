import Foundation
import Testing
import EngelsystemClientKit
@testable import EngelsystemClient

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
    }

    @Test func privacySummaryNamesTheMapMode() {
        #expect(SettingsSummary.privacy(mapLinkRaw: "embedded") == "Embedded map")
        #expect(SettingsSummary.privacy(mapLinkRaw: "linkOnly") == "Link only")
        #expect(SettingsSummary.privacy(mapLinkRaw: "") == "Embedded map")
    }

    @Test func diagnosticsSummaryAndVersion() {
        #expect(SettingsSummary.diagnostics(isEnabled: true) == "Logging on")
        #expect(SettingsSummary.diagnostics(isEnabled: false) == "Logging off")
        #expect(SettingsSummary.version(info: ["CFBundleShortVersionString": "0.1.0"]) == "0.1.0")
        #expect(SettingsSummary.version(info: nil) == "")
        #expect(SettingsSummary.version(info: ["CFBundleShortVersionString": 3]) == "")
    }
}

struct FeaturePresentationTests {
    @Test func statusTextsNameTheReason() {
        func status(_ state: FeatureState, privilege: String? = nil) -> FeatureStatus {
            FeatureStatus(state: state, evidence: .privileges, privilege: privilege, checkedAt: nil)
        }
        #expect(FeaturePresentation.statusText(status(.available)) == "Available")
        #expect(FeaturePresentation.statusText(status(.notAllowed, privilege: "news"))
            == "Not allowed for this account (needs “news”)")
        #expect(FeaturePresentation.statusText(status(.notAllowed)) == "Not allowed for this account")
        #expect(FeaturePresentation.statusText(status(.notOffered)) == "Not offered by this server")
        #expect(FeaturePresentation.statusText(status(.unknown)) == "Not checked yet")
        #expect(Set([FeatureState.available, .notAllowed, .notOffered, .unknown]
            .map { FeaturePresentation.systemImage(status($0)) }).count == 4)
    }

    @Test func summaryAndCheckedTexts() {
        #expect(FeaturePresentation.checkedText(.unknown) == nil)
        let recorded = FeatureStatus(state: .available, evidence: .probe, privilege: nil, checkedAt: Date())
        #expect(FeaturePresentation.checkedText(recorded)?.hasPrefix("Checked ") == true)
    }
}

