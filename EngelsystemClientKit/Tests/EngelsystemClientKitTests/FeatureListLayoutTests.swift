import Testing
@testable import EngelsystemClientKit

struct FeatureListLayoutTests {
    @Test func theListStartsCollapsedOnlyWhenEverythingIsAvailable() {
        #expect(!FeatureListLayout.startsExpanded([.available, .available]))
        #expect(!FeatureListLayout.startsExpanded([]))
        for problem in [FeatureState.notAllowed, .notOffered, .unknown] {
            #expect(FeatureListLayout.startsExpanded([.available, problem]))
        }
    }

    @Test func problemsComeFirstAndTheOrderIsOtherwiseKept() {
        let states: [ServerFeature: FeatureState] = [
            .shifts: .available, .news: .unknown, .newsComments: .notOffered, .locationsList: .available,
            .messages: .notAllowed, .profileWorklogs: .unknown,
        ]
        let ordered = FeatureListLayout.ordered(
            [.shifts, .news, .newsComments, .locationsList, .messages, .profileWorklogs], state: { states[$0] ?? .available })
        #expect(ordered == [.messages, .newsComments, .news, .profileWorklogs, .shifts, .locationsList])
    }
}
