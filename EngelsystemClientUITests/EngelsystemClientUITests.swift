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

        let demoButton = app.buttons["Try Demo Mode"]
        XCTAssertTrue(demoButton.waitForExistence(timeout: 5))
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
        let settingsRow = app.staticTexts["Settings"]
        XCTAssertTrue(settingsRow.waitForExistence(timeout: 5))
        settingsRow.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Demo"].waitForExistence(timeout: 5))

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
    }

    @MainActor
    private func goBack(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
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
