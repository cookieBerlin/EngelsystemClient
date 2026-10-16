//
//  ScreenshotTests.swift
//  EngelsystemClientUITests
//
//  Generates the App Store screenshots (2026-10-12). Not a regression test: run it only through
//  `Scripts/screenshots.sh` (or `-only-testing:EngelsystemClientUITests/ScreenshotTests`), which prepares a
//  clean simulator (English, light appearance, 9:41 status bar) and exports the attachments from the result
//  bundle. Every scene is the Demo Mode instance, seeded by the Debug-only `-seed-demo-instance` launch argument.
//

import XCTest

final class ScreenshotTests: ScreenshotTestCase {
    @MainActor
    func testCaptureAppStoreScreenshots() throws {
        // The first sync triggers the system notification permission alert on a fresh simulator; allow it so it
        // never covers a scene (interruption monitors only fire on a later interaction, hence the taps below).
        allowNotifications()

        let app = XCUIApplication()
        app.launchArguments += ["-seed-demo-instance", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if isPad { XCUIDevice.shared.orientation = .landscapeLeft }
        app.launch()

        // Seeded launch lands on the main page (the sidebar); wait for the first sync to finish.
        XCTAssertTrue(app.staticTexts["Shifts"].waitForExistence(timeout: 30))
        waitForSyncToFinish(in: app, nudge: true)

        // 01 – Shifts
        openSection("Shifts", in: app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Info Desk Shift")).firstMatch.waitForExistence(timeout: 10))
        capture("01-shifts")

        // 02 – News
        openSection("News", in: app)
        XCTAssertTrue(app.staticTexts["Welcome to the Demo Congress!"].waitForExistence(timeout: 10))
        capture("02-news")

        // 03 – Profile
        openSection("Profile", in: app)
        XCTAssertTrue(app.staticTexts["Engel"].waitForExistence(timeout: 10))
        capture("03-profile")

        // 04 – Locations
        openSection("Locations", in: app)
        XCTAssertTrue(app.staticTexts["Locations"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(containing("Chill Space", in: app).waitForExistence(timeout: 10))
        capture("04-locations")

        // 05 – Messages (an open conversation)
        openSection("Messages", in: app)
        let conversation = containing("Helper Angel", in: app)
        XCTAssertTrue(conversation.waitForExistence(timeout: 15))
        conversation.tap()
        XCTAssertTrue(app.staticTexts["Could you cover my shift tomorrow?"].waitForExistence(timeout: 10))
        capture("05-messages")
        if !isPad { goBack(app) } // on iPad the thread is in the detail column; the sidebar stays reachable

        // 06 – Settings
        let settingsButton = app.buttons["Settings"]
        if !isPad && !settingsButton.exists { goBack(app) }
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
        settingsButton.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        // Settings is a hub of topics (Instances, Notifications, …), each with a summary line.
        XCTAssertTrue(app.staticTexts["Instances"].firstMatch.waitForExistence(timeout: 10))
        capture("06-settings")
    }
}
