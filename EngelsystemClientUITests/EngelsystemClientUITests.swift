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

        // The simulator keeps the orientation of a previous test (the launch tests rotate it); a landscape
        // iPhone pushes "Try Demo Mode" below the fold. Every test starts upright.
        if UIDevice.current.userInterfaceIdiom == .phone { XCUIDevice.shared.orientation = .portrait }

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    /// Debug-only `-reset-instances` deletes saved instances; the UserDefaults argument overrides the remembered
    /// last-selected section with an unrecognized value so the app lands on the main list, whatever an earlier
    /// test opened last.
    private static let freshStartArguments = ["-reset-instances", "-mainViewLastSelectedSection", "none"]

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
        app.launchArguments += Self.freshStartArguments
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

        // Demo mode lands on the main page (the sidebar) since 2026-10-12 — the app no
        // longer opens Shifts by default — so open Shifts from there; it syncs the sample shifts.
        openShifts(app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Info Desk Shift")).firstMatch.waitForExistence(timeout: 5))

        // 2026-09-23, user-requested: a shift's location name links to that location's
        // detail screen (Locations feature). Wrapped in a `NavigationLink`/`Label`, so
        // it's exposed as a button, not a static text — same idiom as News's "N
        // Comments" link below.
        let heavenLocationLink = app.buttons["Heaven"].firstMatch // several demo shifts are at Heaven
        XCTAssertTrue(heavenLocationLink.waitForExistence(timeout: 5))
        heavenLocationLink.tap()
        XCTAssertTrue(app.navigationBars["Heaven"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Main hall and central meeting point"].waitForExistence(timeout: 5))
        goBack(app)
        XCTAssertTrue(app.navigationBars["Shifts"].waitForExistence(timeout: 5))

        // Shift detail page (ADR 0015): the row opens it; it shows the shift type, the team by angel
        // type with the occupancy, and — for the own shift — the sign-out hint.
        let firstShiftRow = app.buttons.matching(identifier: "shiftRow")
            .matching(NSPredicate(format: "label CONTAINS %@", "Registration Desk")).firstMatch
        XCTAssertTrue(firstShiftRow.waitForExistence(timeout: 5))
        firstShiftRow.tap()
        XCTAssertTrue(app.navigationBars["Registration Desk"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Info Desk Angel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Demo Angel"].exists || containingText("demo", in: app).exists)
        XCTAssertTrue(app.buttons["Sign out in browser"].waitForExistence(timeout: 5))
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

        // 2026-09-23, Messages feature: the sidebar's "Messages" row only appears once
        // the app-start sync's capability probe confirms the demo instance supports it
        // (`Instance.messagesSupported`, gated so an unsupported server never shows the
        // GUI at all) — several real syncs have already completed by this point in the
        // test, but a generous timeout covers any remaining delay.
        goBack(app)
        let messagesRow = app.staticTexts["Messages"]
        XCTAssertTrue(messagesRow.waitForExistence(timeout: 10))
        messagesRow.tap()
        XCTAssertTrue(app.navigationBars["Messages"].waitForExistence(timeout: 5))

        // Demo mode seeds one conversation with "Helper Angel" (one unread message).
        let helperAngelRow = containingText("Helper Angel", in: app)
        XCTAssertTrue(helperAngelRow.waitForExistence(timeout: 5))
        helperAngelRow.tap()
        XCTAssertTrue(app.navigationBars["Helper Angel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Could you cover my shift tomorrow?"].waitForExistence(timeout: 5))

        // Sending a message — this feature's first write path — round-trips through
        // `APIClient.sendMessage`'s demo branch and appears in the thread immediately.
        let messageField = app.textFields["Message"]
        XCTAssertTrue(messageField.waitForExistence(timeout: 5))
        messageField.tap()
        messageField.typeText("Hello from the UI test")
        app.buttons["Send"].tap()
        XCTAssertTrue(app.staticTexts["Hello from the UI test"].waitForExistence(timeout: 5))

        goBack(app)
        XCTAssertTrue(app.navigationBars["Messages"].waitForExistence(timeout: 5))

        goBack(app)
        // Settings is reached via a gear icon in the sidebar's toolbar corner, not a
        // sidebar row (2026-09-17) — it's app configuration, not a data section on the
        // same level as Shifts/News/Profile.
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        openSettingsPage("Instances", in: app)
        let demoInstanceRow = app.staticTexts["Demo"]
        XCTAssertTrue(demoInstanceRow.waitForExistence(timeout: 5))

        // Editing the instance's name/server (previously not possible after creation —
        // the "Event" section was read-only LabeledContent).
        demoInstanceRow.tap()
        XCTAssertTrue(app.navigationBars["Demo"].waitForExistence(timeout: 5))
        // Everything works in Demo Mode, so the Features list starts collapsed; a tap on the summary opens it.
        let featuresSummary = app.staticTexts["featuresSummary"]
        XCTAssertTrue(featuresSummary.waitForExistence(timeout: 5))
        // A feature row reads as one element ("Shifts, Available, Checked …").
        let shiftsFeature = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Shifts' AND label CONTAINS 'Available'")).firstMatch
        XCTAssertFalse(shiftsFeature.exists)
        featuresSummary.tap()
        XCTAssertTrue(shiftsFeature.waitForExistence(timeout: 5))

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
        XCTAssertTrue(app.navigationBars["Instances"].waitForExistence(timeout: 5))

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

        // Multiple reminders (2026-09-22), on the Notifications page: addable via an "Add Reminder"
        // `Menu`, removable via a visible minus button per row. **Deliberately doesn't depend on
        // the `Menu`'s popup**: XCUITest's interruption check made it unreliable. The test does
        // not assume the default "15 min" row either — the reminders are stored data that earlier
        // runs may have changed — so it removes whichever reminder is there and restores it on a
        // best-effort basis (the add/remove model logic itself is covered by the fast Kit tests).
        goBack(app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        openSettingsPage("Notifications", in: app)
        let addReminderButton = app.buttons["Add Reminder"]
        XCTAssertTrue(addReminderButton.waitForExistence(timeout: 5))
        XCTAssertTrue(addReminderButton.isHittable)

        let removeButtons = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Remove ' AND label ENDSWITH ' min reminder'"))
        let remindersBefore = removeButtons.count
        if remindersBefore > 0 {
            removeButtons.firstMatch.tap()
            let removed = NSPredicate(format: "count == %d", remindersBefore - 1)
            let expectation = XCTNSPredicateExpectation(predicate: removed, object: removeButtons)
            XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed)
            // Best effort: put a reminder back so the next run starts from the same state.
            if addReminderButton.exists {
                addReminderButton.tap()
                let first = app.buttons.matching(NSPredicate(format: "label ENDSWITH ' min'")).firstMatch
                if first.waitForExistence(timeout: 2) { first.tap() }
            }
        }

        // Version/build/git-hash on the About page (AppVersionInfo).
        goBack(app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        openSettingsPage("About", in: app)
        XCTAssertTrue(containingText("Version", in: app).waitForExistence(timeout: 5))
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
    /// 2026-10-12 (backlog C-08): smoke test for screens the demo flow above doesn't reach —
    /// the "new message" user picker, Settings' "Export Diagnostics" sheet (its empty state:
    /// a fresh simulator has received no MetricKit reports) and the debug log. These
    /// SwiftUI files are excluded from the coverage gate (ADR 0010), so this proves they
    /// still render and navigate. Expects `xcrun simctl erase` beforehand, like the others.
    @MainActor
    func testNewMessagePickerExportDiagnosticsAndDebugLogOpen() throws {
        let app = XCUIApplication()
        addUIInterruptionMonitor(withDescription: "Notification permission") { alert in
            for label in ["Allow", "Erlauben", "Don't Allow", "Nicht erlauben"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        app.launchArguments += Self.freshStartArguments
        app.launch()

        let demoButton = app.buttons["Try Demo Mode"]
        XCTAssertTrue(demoButton.waitForExistence(timeout: 5))
        waitUntilHittable(demoButton, in: app)
        demoButton.tap()

        // Main page (sidebar) → Messages → "New Message" → the user picker.
        let messagesRow = app.staticTexts["Messages"]
        XCTAssertTrue(messagesRow.waitForExistence(timeout: 15))
        messagesRow.tap()
        XCTAssertTrue(app.navigationBars["Messages"].waitForExistence(timeout: 5))
        let newMessageButton = app.buttons["New Message"]
        XCTAssertTrue(newMessageButton.waitForExistence(timeout: 5))
        newMessageButton.tap()
        XCTAssertTrue(app.navigationBars["New Message"].waitForExistence(timeout: 10))
        XCTAssertTrue(containingText("Helper Angel", in: app).waitForExistence(timeout: 10))
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Messages"].waitForExistence(timeout: 5))

        // Settings → Export Diagnostics (empty state) → Debug Log.
        goBack(app)
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.navigationBars.firstMatch.tap() // flushes the interruption monitor if needed
        openSettingsPage("Diagnostics", in: app)

        let exportButton = app.buttons["Export Diagnostics"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        exportButton.tap()
        XCTAssertTrue(app.navigationBars["Export Diagnostics"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No reports yet"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].firstMatch.tap()

        let debugLogLink = app.buttons["View Debug Log"]
        XCTAssertTrue(debugLogLink.waitForExistence(timeout: 5))
        debugLogLink.tap()
        XCTAssertTrue(app.navigationBars["Debug Log"].waitForExistence(timeout: 5))
    }

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

        app.launchArguments += Self.freshStartArguments
        app.launch()

        let demoButton = app.buttons["Try Demo Mode"]
        XCTAssertTrue(demoButton.waitForExistence(timeout: 5))
        waitUntilHittable(demoButton, in: app)
        demoButton.tap()
        openShifts(app)
        app.navigationBars.firstMatch.tap() // flushes the interruption monitor if the alert has appeared by now

        goBack(app)
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.navigationBars.firstMatch.tap()
        openSettingsPage("Instances", in: app)

        // The per-device "Parallel Syncs" stepper: Unlimited -> 1 at a time -> back to Unlimited.
        let parallel = app.steppers["parallelSyncsStepper"]
        XCTAssertTrue(parallel.waitForExistence(timeout: 5))
        // The stepper reads as one element: its text (label or value) names the current limit.
        func parallelText() -> String { "\(parallel.label) \(parallel.value as? String ?? "")" }
        XCTAssertTrue(parallelText().contains("Unlimited"), parallelText())
        parallel.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(parallelText().contains("1 at a time"), parallelText())
        parallel.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(parallelText().contains("Unlimited"), parallelText())

        let activeToggle = app.switches["Demo Active"]
        XCTAssertTrue(activeToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(activeToggle.value as? String, "1")
        activeToggle.tap()
        app.navigationBars.firstMatch.tap()
        XCTAssertEqual(activeToggle.value as? String, "0")

        goBack(app) // Settings hub
        goBack(app) // sidebar

        let addInstanceButton = app.buttons["Add Instance"]
        XCTAssertTrue(addInstanceButton.waitForExistence(timeout: 5))
        addInstanceButton.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        openSettingsPage("Instances", in: app)

        // Leave the instance re-activated rather than deactivated, in case a later
        // test run reuses the same simulator/app state.
        let reactivateToggle = app.switches["Demo Active"]
        XCTAssertTrue(reactivateToggle.waitForExistence(timeout: 5))
        if reactivateToggle.value as? String == "0" {
            reactivateToggle.tap()
            XCTAssertEqual(reactivateToggle.value as? String, "1")
        }

        // The main page's footer shows how fresh the instance's data is, and the switch refreshed it.
        goBack(app) // Settings hub
        goBack(app) // sidebar
        XCTAssertTrue(app.buttons["freshness-Demo"].waitForExistence(timeout: 10))
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

        app.launchArguments += Self.freshStartArguments
        app.launch()

        let demoButton = app.buttons["Try Demo Mode"]
        XCTAssertTrue(demoButton.waitForExistence(timeout: 5))
        waitUntilHittable(demoButton, in: app)
        demoButton.tap()
        openShifts(app)
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
        app.launchArguments += Self.freshStartArguments
        app.launch()

        let demoButton = app.buttons["Try Demo Mode"]
        XCTAssertTrue(demoButton.waitForExistence(timeout: 5))
        waitUntilHittable(demoButton, in: app)
        demoButton.tap()
        openShifts(app)

        goBack(app)
        XCTAssertTrue(app.staticTexts["News"].waitForExistence(timeout: 5))
        app.swipeDown()
        XCTAssertTrue(app.staticTexts["News"].waitForExistence(timeout: 5))

        app.staticTexts["Shifts"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Shifts"].waitForExistence(timeout: 5))
        app.swipeDown()
        XCTAssertTrue(app.navigationBars["Shifts"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Info Desk Shift")).firstMatch.waitForExistence(timeout: 5))
    }

    /// The Shifts menu: Upcoming hides the past shift, Past shows only it, All with Latest First reverses the order.
    @MainActor
    func testShiftFilterAndSortMenu() throws {
        let app = XCUIApplication()
        app.launchArguments += Self.freshStartArguments
        app.launch()

        let demoButton = app.buttons["Try Demo Mode"]
        XCTAssertTrue(demoButton.waitForExistence(timeout: 5))
        waitUntilHittable(demoButton, in: app)
        demoButton.tap()
        openShifts(app)

        func shift(_ title: String) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        }
        func choose(_ item: String) {
            app.buttons["shiftFilterMenu"].tap()
            let entry = app.buttons[item]
            XCTAssertTrue(entry.waitForExistence(timeout: 5), item)
            entry.tap()
        }

        // Default "Upcoming": the shift that is over (Set-up Shift) is not listed.
        XCTAssertTrue(shift("Info Desk Shift").waitForExistence(timeout: 10))
        XCTAssertFalse(shift("Set-up Shift").exists)

        choose("Past")
        XCTAssertTrue(shift("Set-up Shift").waitForExistence(timeout: 5))
        XCTAssertFalse(shift("Info Desk Shift").exists)

        choose("All")
        XCTAssertTrue(shift("Info Desk Shift").waitForExistence(timeout: 5))
        XCTAssertTrue(shift("Set-up Shift").exists)

        // The first row follows the sort order (the rows below the first screen are not built yet).
        func firstRowHas(_ title: String) -> Bool {
            app.cells.element(boundBy: 0).buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch.exists
        }
        XCTAssertTrue(firstRowHas("Set-up Shift"))
        choose("Latest First")
        XCTAssertTrue(shift("Late Night Info Desk").waitForExistence(timeout: 5))
        XCTAssertTrue(firstRowHas("Late Night Info Desk"))

        // Leave the defaults behind for the next run on this simulator.
        choose("Earliest First")
        choose("Upcoming")
    }

    /// Two instances in "Sectioned" mode: each gets a band with its name that folds its content away.
    @MainActor
    func testInstanceBandsFold() throws {
        let app = XCUIApplication()
        app.launchArguments += Self.freshStartArguments
        // The display mode setting, given as a launch argument (it overrides the stored preference).
        app.launchArguments += ["-multiInstanceDisplayMode", "sectioned"]
        app.launch()

        let demoButton = app.buttons["Try Demo Mode"]
        XCTAssertTrue(demoButton.waitForExistence(timeout: 5))
        waitUntilHittable(demoButton, in: app)
        demoButton.tap()
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        openSettingsPage("Instances", in: app)

        // A second (demo) instance.
        app.buttons["Add Instance"].tap()
        let name = app.textFields["Name (e.g. 42C3)"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Second")
        let server = app.textFields["https://engelsystem.example.org"]
        server.tap()
        server.typeText("demo://engelsystem.local")
        let key = app.secureTextFields["API Key"]
        key.tap()
        key.typeText("demo")
        app.buttons["Test Connection"].tap()
        XCTAssertTrue(app.staticTexts["Connection Verified"].waitForExistence(timeout: 10))
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Instances"].waitForExistence(timeout: 10))

        // Back to the main list (Instances -> Settings hub -> main list), one tap per level.
        for _ in 0..<3 {
            let back = app.buttons["BackButton"].firstMatch
            guard back.waitForExistence(timeout: 3) else { break }
            back.tap()
            if app.staticTexts["Shifts"].waitForExistence(timeout: 3) { break }
        }
        let shiftsRow = app.staticTexts["Shifts"]
        XCTAssertTrue(shiftsRow.waitForExistence(timeout: 10))
        shiftsRow.tap()
        XCTAssertTrue(app.navigationBars["Shifts"].waitForExistence(timeout: 10))

        let demoBand = app.buttons["instanceHeader-Demo"]
        // (An instance without any synced shifts has no band yet, so only the first one is checked.)
        XCTAssertTrue(demoBand.waitForExistence(timeout: 10))
        let infoDesk = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Info Desk Shift")).firstMatch
        XCTAssertTrue(infoDesk.waitForExistence(timeout: 5))

        // Folding the instance hides its shifts, folding again brings them back.
        demoBand.tap()
        XCTAssertTrue(infoDesk.waitForNonExistence(timeout: 5) || !infoDesk.isHittable)
        XCTAssertTrue(demoBand.exists)
        demoBand.tap()
        XCTAssertTrue(infoDesk.waitForExistence(timeout: 5))
    }

    /// Tapping the freshness line starts a sync whose banner offers "Stop sync".
    @MainActor
    func testStopSyncAsksForConfirmation() throws {
        let app = XCUIApplication()
        app.launchArguments += Self.freshStartArguments
        app.launch()

        let demoButton = app.buttons["Try Demo Mode"]
        XCTAssertTrue(demoButton.waitForExistence(timeout: 5))
        waitUntilHittable(demoButton, in: app)
        demoButton.tap()
        openShifts(app)
        goBack(app)

        // Let the app-start sync finish, then start another one from the footer.
        let banner = app.otherElements["syncProgressBanner"]
        if banner.waitForExistence(timeout: 3) {
            XCTAssertTrue(banner.waitForNonExistence(timeout: 30))
        }
        let freshness = app.buttons["freshness-Demo"]
        XCTAssertTrue(freshness.waitForExistence(timeout: 10))
        freshness.tap()

        // The banner lists the instance and offers "Stop sync". The confirmation dialog itself is not driven
        // here: the demo sync ends within a few seconds, so tapping through the dialog would race the banner.
        XCTAssertTrue(app.buttons["stopSyncButton"].waitForExistence(timeout: 5))
    }

    @MainActor
    /// Demo mode lands on the main page (the sidebar), not Shifts (2026-10-12): open Shifts from there.
    private func openShifts(_ app: XCUIApplication) {
        let shiftsRow = app.staticTexts["Shifts"]
        XCTAssertTrue(shiftsRow.waitForExistence(timeout: 10))
        shiftsRow.tap()
        XCTAssertTrue(app.navigationBars["Shifts"].waitForExistence(timeout: 5))
    }

    private func goBack(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    /// Opens one page of the Settings hub (Instances, Notifications, Sync, Phone Numbers, Privacy,
    /// Diagnostics, About). The rows carry a summary, so the label only *starts with* the title.
    private func openSettingsPage(_ title: String, in app: XCUIApplication) {
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
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
