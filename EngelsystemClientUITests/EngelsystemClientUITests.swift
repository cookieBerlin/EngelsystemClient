//
//  EngelsystemClientUITests.swift
//  EngelsystemClientUITests
//
//  Created by Angelo Cuccato on 31.08.26.
//

import XCTest

final class EngelsystemClientUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation
    }

    @MainActor
    func testDemoModeNavigationFlow() throws {
        let app = XCUIApplication()
        app.launch()

        // LaunchScreenView (icon/app name/version) shows for a fixed, short duration
        // (ContentView.launchScreenDuration) from when SwiftUI first renders it — not
        // from process launch. Deliberately not asserted here: on a slow/loaded machine,
        // cold launch overhead before XCUITest can even query the accessibility
        // hierarchy can exceed that whole window on its own, making an existence check
        // for it a race against test-harness startup rather than a check of real
        // behavior (confirmed hands-on: failed at a 5s timeout after an 11s+ cold
        // launch). The launch screen is exercised structurally instead — it's what
        // ContentView shows first, so if it crashed or broke ContentView's body, none
        // of this test's later assertions would ever get to run.
        //
        // It briefly overlays real content (icon/app name/version, shown
        // for ContentView.launchScreenDuration) — it exists in the accessibility tree
        // immediately, so `waitForExistence` alone isn't enough to know it's safe to
        // tap; wait for it to actually be hittable (splash gone) first.
        let demoButton = app.buttons["Try Demo Mode"]
        XCTAssertTrue(demoButton.waitForExistence(timeout: 5))
        waitUntilHittable(demoButton, in: app)
        demoButton.tap()

        // Demo mode lands on Shifts by default and syncs the sample shifts.
        XCTAssertTrue(app.navigationBars["Shifts"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Info Desk Shift"].waitForExistence(timeout: 5))

        // 2026-09-23, user-requested: a shift's location name links to that location's
        // detail screen (Locations feature). Wrapped in a `NavigationLink`/`Label`, so
        // it's exposed as a button, not a static text — same idiom as News's "N
        // Comments" link below.
        let heavenLocationLink = app.buttons["Heaven"]
        XCTAssertTrue(heavenLocationLink.waitForExistence(timeout: 5))
        heavenLocationLink.tap()
        XCTAssertTrue(app.navigationBars["Heaven"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Main hall and central meeting point"].waitForExistence(timeout: 5))
        goBack(app)
        XCTAssertTrue(app.navigationBars["Shifts"].waitForExistence(timeout: 5))

        goBack(app)
        let newsRow = app.staticTexts["News"]
        XCTAssertTrue(newsRow.waitForExistence(timeout: 5))
        newsRow.tap()
        XCTAssertTrue(app.navigationBars["News"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Welcome to the Demo Congress!"].waitForExistence(timeout: 5))

        goBack(app)
        let profileRow = app.staticTexts["Profile"]
        XCTAssertTrue(profileRow.waitForExistence(timeout: 5))
        profileRow.tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 5))
        // LabeledContent's value isn't exposed as a standalone exact-match static text,
        // so match on any element whose accessibility label contains the name instead.
        XCTAssertTrue(containingText("Demo Angel", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Engel"].waitForExistence(timeout: 5))

        // 2026-09-23, user-requested: new "Locations" sidebar entry, listing every
        // location and linking to its own detail screen. `LocationRow`'s label is a
        // plain `VStack` of two `Text` views (name + description), not a `Label` —
        // SwiftUI/UIKit combines that into a single accessibility element (exposed as
        // a button) rather than two independent static texts, so this matches via
        // `containingText` (already used above for a similar "can't do an exact
        // static-text match" case) instead of an exact `staticTexts[...]` lookup.
        goBack(app)
        let locationsRow = app.staticTexts["Locations"]
        XCTAssertTrue(locationsRow.waitForExistence(timeout: 5))
        locationsRow.tap()
        XCTAssertTrue(app.navigationBars["Locations"].waitForExistence(timeout: 5))
        let chillSpaceRow = containingText("Chill Space", in: app)
        XCTAssertTrue(chillSpaceRow.waitForExistence(timeout: 5))
        chillSpaceRow.tap()
        XCTAssertTrue(app.navigationBars["Chill Space"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Quiet area to rest between shifts"].waitForExistence(timeout: 5))
        goBack(app)
        XCTAssertTrue(app.navigationBars["Locations"].waitForExistence(timeout: 5))

        goBack(app)
        // Settings is reached via a gear icon in the sidebar's toolbar corner, not a
        // sidebar row (2026-09-17) — it's app configuration, not a data section on the
        // same level as Shifts/News/Profile.
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let demoInstanceRow = app.staticTexts["Demo"]
        XCTAssertTrue(demoInstanceRow.waitForExistence(timeout: 5))

        // Editing the instance's name/server (previously not possible after creation —
        // the "Event" section was read-only LabeledContent).
        demoInstanceRow.tap()
        XCTAssertTrue(app.navigationBars["Demo"].waitForExistence(timeout: 5))
        let editButton = app.buttons["Edit Instance"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 5))
        editButton.tap()

        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        if let existingValue = nameField.value as? String, !existingValue.isEmpty {
            nameField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existingValue.count))
        }
        nameField.typeText("Demo Renamed")

        app.buttons["Save"].tap()
        // Saving re-tests the connection (demo mode resolves instantly, no real
        // network) and dismisses back to the instance detail view on success.
        XCTAssertTrue(app.navigationBars["Demo Renamed"].waitForExistence(timeout: 10))
        XCTAssertTrue(containingText("Demo Renamed", in: app).waitForExistence(timeout: 5))

        goBack(app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        // 2026-09-22: superseded the "Active"/"Inactive" sections + swipe-action
        // design — back to a single flat list with a per-row Toggle (accessibility
        // label "<name> Active", since `.labelsHidden()` + an `EmptyView()` label
        // otherwise leaves it unnamed).
        let activeToggle = app.switches["Demo Renamed Active"]
        XCTAssertTrue(activeToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(activeToggle.value as? String, "1")
        activeToggle.tap()
        XCTAssertEqual(activeToggle.value as? String, "0")
        activeToggle.tap()
        XCTAssertEqual(activeToggle.value as? String, "1")

        // Multiple reminders (2026-09-22): defaults to a single "15 min" row,
        // addable via an "Add Reminder" `Menu`, removable via a visible minus button
        // per row. **Deliberately doesn't tap into the `Menu`'s own popup content**:
        // tried it, hit it consistently closing/not registering before the item
        // could be found (XCUITest's automatic "check for interrupting elements"
        // step before every subsequent interaction is the leading suspect — menus
        // aren't a UI pattern this project's tests had exercised before). Verified
        // instead via the fast, reliable `EngelsystemClientKitTests
        // .notificationLeadTimeSettings...` tests (the actual add/remove model
        // logic) plus checking the button itself exists and is tappable here. The
        // remove path — a plain button, no popup — is still verified end-to-end.
        XCTAssertTrue(containingText("15 min", in: app).waitForExistence(timeout: 5))
        let addReminderButton = app.buttons["Add Reminder"]
        XCTAssertTrue(addReminderButton.waitForExistence(timeout: 5))
        XCTAssertTrue(addReminderButton.isHittable)

        // Remove the default "15 min" reminder via its visible minus button.
        let removeFifteenMin = app.buttons["Remove 15 min reminder"]
        XCTAssertTrue(removeFifteenMin.waitForExistence(timeout: 5))
        removeFifteenMin.tap()
        XCTAssertFalse(app.buttons["Remove 15 min reminder"].waitForExistence(timeout: 2))

        // Version/build/git-hash footer at the bottom of Settings (AppVersionInfo) —
        // scroll down since it sits below the fold after all the sections above.
        let versionFooter = containingText("Version", in: app)
        for _ in 0..<10 where !versionFooter.exists {
            app.swipeUp()
        }
        XCTAssertTrue(versionFooter.waitForExistence(timeout: 5))
    }

    /// 2026-09-22, user-reported and fixed: with zero active instances, `MainView`'s
    /// sidebar shows a dedicated empty state (message + "Add Instance" button)
    /// instead of the normal Shifts/News/Profile rows — but an earlier version of that
    /// fix silently failed to navigate anywhere when the button (or the toolbar
    /// Settings gear) was tapped, because it replaced the sidebar's `List(selection:)`
    /// entirely with a `ContentUnavailableView` instead of keeping the same `List`
    /// and just changing its rows. `NavigationSplitView`'s automatic column push on
    /// compact width only fires when the sidebar's content is that `List`. This test
    /// exercises exactly the reported flow: deactivate the only instance, confirm the
    /// empty state appears, and confirm tapping its button actually reaches Settings.
    @MainActor
    func testAddInstanceButtonAppearsAndNavigatesWhenNoActiveInstance() throws {
        let app = XCUIApplication()

        // A fresh simulator (this test expects `xcrun simctl erase` beforehand, same
        // as `testDemoModeNavigationFlow`) shows the real system notification
        // permission alert the first time Shifts syncs — asynchronously, so it can
        // appear at any point afterward, not necessarily right when the sync call
        // itself returns. This test reaches the "Demo Active" toggle much sooner
        // after that first sync than `testDemoModeNavigationFlow` does (fewer
        // intermediate screens), which turned out to make it much more likely to
        // land squarely on that alert's timing window and swallow the toggle tap —
        // confirmed hands-on (the toggle's value silently failed to flip after
        // `.tap()`). Same fix as documented for the Watch UI tests: a monitor plus a
        // no-op tap afterward, since interruption monitors only fire on a subsequent
        // interaction, not proactively. Locale-dependent label, matching both.
        addUIInterruptionMonitor(withDescription: "Notification permission") { alert in
            for label in ["Allow", "Erlauben"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            for label in ["Don't Allow", "Nicht erlauben"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }

        app.launch()

        let demoButton = app.buttons["Try Demo Mode"]
        XCTAssertTrue(demoButton.waitForExistence(timeout: 5))
        waitUntilHittable(demoButton, in: app)
        demoButton.tap()
        XCTAssertTrue(app.navigationBars["Shifts"].waitForExistence(timeout: 5))
        app.navigationBars.firstMatch.tap() // flushes the interruption monitor if the alert has appeared by now

        goBack(app)
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.navigationBars.firstMatch.tap()

        let activeToggle = app.switches["Demo Active"]
        XCTAssertTrue(activeToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(activeToggle.value as? String, "1")
        activeToggle.tap()
        app.navigationBars.firstMatch.tap()
        XCTAssertEqual(activeToggle.value as? String, "0")

        goBack(app)

        let addInstanceButton = app.buttons["Add Instance"]
        XCTAssertTrue(addInstanceButton.waitForExistence(timeout: 5))
        addInstanceButton.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        // Leave the instance re-activated rather than deactivated, in case a later
        // test run reuses the same simulator/app state.
        let reactivateToggle = app.switches["Demo Active"]
        XCTAssertTrue(reactivateToggle.waitForExistence(timeout: 5))
        if reactivateToggle.value as? String == "0" {
            reactivateToggle.tap()
            XCTAssertEqual(reactivateToggle.value as? String, "1")
        }
    }

    /// 2026-09-22, user-reported (twice): tapping "Read More" on a News row was also
    /// silently activating that row's "N Comments" `NavigationLink` at the same time
    /// — a `List` row quirk where an unstyled `Button` sitting in the same row as a
    /// `NavigationLink` can have its tap "fall through" into the row's navigation
    /// too. Fixed with `.buttonStyle(.plain)` on the Read More/Show Less button.
    /// Demo item 1 is the only demo post with both a `[more]` split *and* comments,
    /// specifically so this combination is exercisable at all.
    @MainActor
    func testReadMoreDoesNotAlsoOpenComments() throws {
        let app = XCUIApplication()
        addUIInterruptionMonitor(withDescription: "Notification permission") { alert in
            for label in ["Allow", "Erlauben"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            for label in ["Don't Allow", "Nicht erlauben"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }

        app.launch()

        let demoButton = app.buttons["Try Demo Mode"]
        XCTAssertTrue(demoButton.waitForExistence(timeout: 5))
        waitUntilHittable(demoButton, in: app)
        demoButton.tap()
        XCTAssertTrue(app.navigationBars["Shifts"].waitForExistence(timeout: 5))
        app.navigationBars.firstMatch.tap() // flushes the interruption monitor if needed

        goBack(app)
        let newsRow = app.staticTexts["News"]
        XCTAssertTrue(newsRow.waitForExistence(timeout: 5))
        newsRow.tap()
        XCTAssertTrue(app.navigationBars["News"].waitForExistence(timeout: 5))

        let readMoreButton = app.buttons["Read More"]
        XCTAssertTrue(readMoreButton.waitForExistence(timeout: 5))
        readMoreButton.tap()

        // The bug: this tap also activated the Comments NavigationLink, pushing a
        // detail screen and leaving the News navigation bar behind.
        XCTAssertTrue(app.navigationBars["News"].waitForExistence(timeout: 3))
        let showLessButton = app.buttons["Show Less"]
        XCTAssertTrue(showLessButton.waitForExistence(timeout: 5))

        // Same check in the other direction: collapsing must not open Comments either.
        showLessButton.tap()
        XCTAssertTrue(app.navigationBars["News"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Read More"].waitForExistence(timeout: 5))

        // The Comments link itself must still actually work when tapped directly.
        let commentsLink = app.buttons["2 Comments"]
        XCTAssertTrue(commentsLink.waitForExistence(timeout: 5))
        commentsLink.tap()
        XCTAssertTrue(app.navigationBars["Welcome to the Demo Congress!"].waitForExistence(timeout: 5))
    }

    /// 2026-09-22, user-requested: the main page (the sidebar list) should support
    /// pull-to-refresh too, and it — like Shifts/News/Profile's own pull-to-refresh —
    /// should show the same `SyncProgressBanner` the app-start sync does.
    ///
    /// **Deliberately does not assert the banner text itself appears** — tried this
    /// first via a real gesture (both `.swipeDown()` and a manual slow press-then-drag)
    /// and hit the same class of problem CLAUDE.md already documents for the launch
    /// screen: a short-lived transient element is inherently racy to catch via
    /// XCUITest, and in this case dramatically more so — gesture synthesis for a
    /// slow drag took **~60 real seconds** to settle in this Simulator, by which point
    /// the banner (a demo-mode sync, done in under 2s including its own 1.2s success
    /// flash) had already come and gone long before the test could even start
    /// checking. Confirmed hands-on, not assumed. Verified instead via the fast,
    /// reliable `EngelsystemClientTests.MainSyncStatusTests.run.../runCoordinated...`
    /// unit tests (the actual state-machine logic) plus code review (the `.refreshable`
    /// wiring here is structurally identical to Shifts/News/Profile's pre-existing,
    /// already-proven pull-to-refresh, just wrapped in `syncStatus.run`/
    /// `.runCoordinated`). This test instead confirms the mechanical, non-flaky part:
    /// pulling to refresh (via the fast default `swipeDown()`, regardless of whether
    /// it crosses `.refreshable`'s pull threshold) doesn't break navigation, on both
    /// the sidebar itself and a pushed detail screen.
    @MainActor
    func testPullToRefreshOnMainPageDoesNotBreakNavigation() throws {
        let app = XCUIApplication()
        app.launch()

        let demoButton = app.buttons["Try Demo Mode"]
        XCTAssertTrue(demoButton.waitForExistence(timeout: 5))
        waitUntilHittable(demoButton, in: app)
        demoButton.tap()
        XCTAssertTrue(app.navigationBars["Shifts"].waitForExistence(timeout: 5))

        goBack(app)
        XCTAssertTrue(app.staticTexts["News"].waitForExistence(timeout: 5))
        app.swipeDown()
        XCTAssertTrue(app.staticTexts["News"].waitForExistence(timeout: 5))

        app.staticTexts["Shifts"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Shifts"].waitForExistence(timeout: 5))
        app.swipeDown()
        XCTAssertTrue(app.navigationBars["Shifts"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Info Desk Shift"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func goBack(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    @MainActor
    private func containingText(_ text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    /// `waitForExistence` only checks that an element is in the accessibility tree, not
    /// that it's actually tappable — an element under an opaque overlay (like
    /// `LaunchScreenView`) still "exists". Used wherever a launch-time overlay could
    /// still be covering the real content when the element first appears.
    @MainActor
    private func waitUntilHittable(_ element: XCUIElement, in app: XCUIApplication, timeout: TimeInterval = 5) {
        let predicate = NSPredicate(format: "isHittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        _ = XCTWaiter.wait(for: [expectation], timeout: timeout)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
