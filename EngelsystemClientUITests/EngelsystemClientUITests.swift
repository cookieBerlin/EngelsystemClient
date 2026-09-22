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

        // Notification lead-time picker defaults to 15 min and can be changed.
        // Its exact accessibility element type/label depend on the system-rendered
        // Picker style (menu vs. pushed list), so match loosely by contained text
        // rather than assuming a specific element kind or exact label.
        let leadTimeRow = containingText("Notify Before Shift", in: app)
        XCTAssertTrue(leadTimeRow.waitForExistence(timeout: 5))
        XCTAssertTrue(containingText("15 min", in: app).waitForExistence(timeout: 5))
        // The row's own label isn't the hittable element (the Picker control overlays
        // it), so tap by coordinate instead of `.tap()` on the label element itself.
        leadTimeRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let thirtyMinOption = containingText("30 min", in: app)
        XCTAssertTrue(thirtyMinOption.waitForExistence(timeout: 5))
        thirtyMinOption.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(containingText("30 min", in: app).waitForExistence(timeout: 5))

        // Version/build/git-hash footer at the bottom of Settings (AppVersionInfo) —
        // scroll down since it sits below the fold after all the sections above.
        let versionFooter = containingText("Version", in: app)
        for _ in 0..<10 where !versionFooter.exists {
            app.swipeUp()
        }
        XCTAssertTrue(versionFooter.waitForExistence(timeout: 5))
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
