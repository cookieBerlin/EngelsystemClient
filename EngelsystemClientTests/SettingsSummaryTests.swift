import Foundation
import Testing
import EngelsystemClientKit
@testable import EngelsystemClient

struct SettingsSummaryTests {
    @Test func privacySummaryNamesTheMapMode() {
        #expect(SettingsSummary.privacy(mapLinkRaw: "embedded") == "Embedded map")
        #expect(SettingsSummary.privacy(mapLinkRaw: "linkOnly") == "Link only")
        #expect(SettingsSummary.privacy(mapLinkRaw: "") == "Embedded map")
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

