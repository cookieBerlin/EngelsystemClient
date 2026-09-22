//
//  EngelsystemClient_Watch_AppUITests.swift
//  EngelsystemClient Watch AppUITests
//
//  Created by Angelo Cuccato on 31.08.26.
//

import XCTest

final class EngelsystemClient_Watch_AppUITests: XCTestCase {

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

    // NOTE: early runs of this test (before the timeout/scroll fixes below) failed
    // inconsistently on different assertions each time — watchOS simulator cold-launch
    // and lazily-materialized Form accessibility elements need real headroom. It now
    // passes consistently; if it ever regresses, cross-check against a manual simulator
    // screenshot and EngelsystemClientKit's unit tests (which cover the actual business
    // logic this view exercises) before assuming an app defect vs. environment flakiness.
    @MainActor
    func testDemoModeShowsNextShift() throws {
        let app = XCUIApplication()

        // A fresh install triggers the real system notification-permission alert on the
        // first sync (NotificationScheduler.requestAuthorizationIfNeeded), which is a
        // separate springboard-hosted process (com.apple.Carousel on watchOS) that can
        // steal a tap meant for our app mid-test if left undismissed. An interruption
        // monitor only fires on a subsequent UI interaction, so pair this with a no-op
        // tap wherever the alert might have appeared (see below).
        addUIInterruptionMonitor(withDescription: "Notification permission") { alert in
            // The simulator's locale determines the button label ("Allow" vs. the
            // German "Erlauben" seen in this environment) — try both rather than
            // assuming English.
            for label in ["Allow", "Erlauben"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }

        app.launch()

        // ContentView now goes straight to Settings when no instance is configured yet
        // (2026-09-18, at the user's request) rather than the manual-entry Setup screen
        // — since Instance now syncs via CloudKit unconditionally, an instance created
        // on the iPhone should just appear here on its own, and showing Settings first
        // lets the user watch the CloudSyncStatus footer to confirm that's happening,
        // instead of being steered straight into manual entry as if sync wasn't an
        // option. Setup (manual entry / "Try Demo Mode") is one tap away via Settings'
        // "Add Instance" button. watchOS simulator cold launch is slow — give it more
        // room than the iOS test needs.
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 30))

        let addInstanceButton = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Add Instance"))
            .firstMatch
        for _ in 0..<10 where !addInstanceButton.exists {
            app.swipeUp()
        }
        XCTAssertTrue(addInstanceButton.waitForExistence(timeout: 10))
        addInstanceButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(app.navigationBars["Setup"].waitForExistence(timeout: 15))

        // The Form's later sections aren't materialized in the accessibility tree until
        // scrolled into view, so swipe up until the button appears (bounded to avoid an
        // infinite loop if something else is wrong). Matched broadly by label, not just
        // `.buttons`, since watchOS may expose a Form row button as a different element type.
        let demoButton = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Try Demo Mode"))
            .firstMatch
        for _ in 0..<10 where !demoButton.exists {
            app.swipeUp()
        }
        XCTAssertTrue(demoButton.waitForExistence(timeout: 5))
        demoButton.tap()

        // Creating the instance flips ContentView's root from WatchSettingsView (which
        // presented this Setup sheet) to WatchMainView underneath — if that teardown
        // doesn't also dismiss an already-presented sheet on its own, close it
        // explicitly via watchOS's auto-added sheet "Close" button.
        let closeSetupSheetButton = app.buttons["Close"].firstMatch
        if closeSetupSheetButton.waitForExistence(timeout: 3) {
            closeSetupSheetButton.tap()
        }

        XCTAssertTrue(app.navigationBars["Next Shift"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Info Desk Shift"].waitForExistence(timeout: 15))

        // Force any pending notification-permission alert to be caught and dismissed by
        // the interruption monitor above before continuing — it only fires on a
        // subsequent UI interaction, not proactively.
        app.tap()

        // Settings now exists on the Watch too, mirroring the iOS app's Settings screen
        // (instance management + notification lead time) — a plain in-content
        // NavigationLink row below the sync status, not a toolbar item (watchOS's
        // compact navigation bar doesn't reliably render a bare `ToolbarItem`). May need
        // scrolling into view, same as the demo button above.
        let settingsButton = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Settings"))
            .firstMatch
        for _ in 0..<10 where !settingsButton.exists {
            app.swipeUp()
        }
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
        settingsButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 15))

        // watchOS List rows expose as `.cell`, unlike the loosely-matched rows above.
        let demoInstanceRow = app.cells["Demo"]
        XCTAssertTrue(demoInstanceRow.waitForExistence(timeout: 10))
        demoInstanceRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        // Wait for the push itself to land (navigation title is the instance name) before
        // checking its content — decouples "did navigation happen" from "is this specific
        // label rendered yet", which was flaky when checked together under one timeout.
        XCTAssertTrue(app.navigationBars["Demo"].waitForExistence(timeout: 15))

        // Editing the instance (combined name/server/User ID/API Key dialog since the
        // 2026-09-17 multi-active-instance redesign — previously two separate actions).
        // Visible without scrolling — it's the first section's fourth row.
        let editButton = app.buttons["Edit Instance"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 15))
        editButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["Edit Instance"].waitForExistence(timeout: 15))
        XCTAssertTrue(containingText("Demo", in: app).waitForExistence(timeout: 10))
        // watchOS auto-adds a "Close" (xmark) button to a sheet's navigation bar —
        // nested Button elements share the same label, so `.firstMatch` to avoid an
        // ambiguous-match error.
        let closeButton = app.buttons["Close"].firstMatch
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        closeButton.tap()

        // The only instance defaults to active on creation, so its detail view's
        // Status row reads "Active" — there's no separate "Update API Key" action
        // anymore (folded into "Edit Instance" above) or "Use as Active Instance"
        // button (activation now happens via a swipe action on the Settings list, not
        // from the detail screen). Adding the Edit row above pushed this below the
        // fold, so it now needs scrolling too.
        let statusLabel = containingText("Active", in: app)
        for _ in 0..<10 where !statusLabel.exists {
            app.swipeUp()
        }
        XCTAssertTrue(statusLabel.waitForExistence(timeout: 15))
        // "Remove Instance" isn't materialized in the accessibility tree until scrolled
        // into view — same as the Setup form.
        let removeInstanceButton = app.buttons["Remove Instance"]
        for _ in 0..<10 where !removeInstanceButton.exists {
            app.swipeUp()
        }
        XCTAssertTrue(removeInstanceButton.waitForExistence(timeout: 10))

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))

        // Notification lead-time picker defaults to 15 min and can be changed —
        // same loose-matching + coordinate-tap approach as the iOS UI test, since the
        // system Picker control's hittable region doesn't coincide with its label.
        let leadTimeRow = containingText("Notify Before Shift", in: app)
        XCTAssertTrue(leadTimeRow.waitForExistence(timeout: 15))
        XCTAssertTrue(containingText("15 min", in: app).waitForExistence(timeout: 15))
        leadTimeRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let thirtyMinOption = containingText("30 min", in: app)
        XCTAssertTrue(thirtyMinOption.waitForExistence(timeout: 10))
        thirtyMinOption.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(containingText("30 min", in: app).waitForExistence(timeout: 10))
    }

    @MainActor
    private func containingText(_ text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
