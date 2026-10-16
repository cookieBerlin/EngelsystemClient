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

final class ScreenshotTests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureAppStoreScreenshots() throws {
        // The first sync triggers the system notification permission alert on a fresh simulator; allow it so it
        // never covers a scene (interruption monitors only fire on a later interaction, hence the taps below).
        addUIInterruptionMonitor(withDescription: "Notification permission") { alert in
            for label in ["Allow", "Erlauben"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }

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

    // MARK: - Helpers

    /// Opens a sidebar section: on iPhone from the main page (the previous screen is popped first), on iPad
    /// directly from the always-visible sidebar.
    @MainActor
    private func openSection(_ title: String, in app: XCUIApplication) {
        let row = app.staticTexts[title]
        if !row.exists || !row.isHittable { goBack(app) }
        XCTAssertTrue(row.waitForExistence(timeout: 10), "sidebar row \(title)")
        row.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10), "screen \(title)")
        waitForSyncToFinish(in: app)
    }

    /// Waits until the sync banner is gone. The sync's last step asks for notification permission on a fresh
    /// simulator and only finishes once that prompt is answered — and the prompt only comes up after a real
    /// interaction with the app, at a moment that depends on how busy the (new) simulator is (found with the app's
    /// debug log: the sync steps take ~2 s, then it waits on the permission request). So `nudge` repeats: it taps
    /// Settings and returns, and answers a visible permission alert directly via SpringBoard, until the banner is gone.
    @MainActor
    private func waitForSyncToFinish(in app: XCUIApplication, nudge: Bool = false, timeout: TimeInterval = 300) {
        let banner = app.descendants(matching: .any)["syncProgressBanner"]
        _ = banner.waitForExistence(timeout: 3)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deadline = Date().addingTimeInterval(timeout)
        while banner.exists && Date() < deadline {
            if nudge {
                app.buttons["Settings"].tap()
                _ = app.navigationBars["Settings"].waitForExistence(timeout: 20)
                if !isPad { goBack(app) }
            }
            for label in ["Allow", "Erlauben"] where springboard.alerts.buttons[label].exists {
                springboard.alerts.buttons[label].tap()
            }
            Thread.sleep(forTimeInterval: 4)
        }
        XCTAssertFalse(banner.exists, "sync banner still visible")
        Thread.sleep(forTimeInterval: 1.5) // lets list animations settle
    }

    @MainActor
    private func goBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists { back.tap() }
    }

    @MainActor
    private func containing(_ text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Full-screen capture (status bar included), kept in the result bundle under `name`; the script exports it.
    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
