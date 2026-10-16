//
//  ScreenshotTestCase.swift
//  EngelsystemClientUITests
//
//  Shared helpers of the two screenshot test classes (App Store set: ScreenshotTests; every screen for the guide:
//  ManualScreenshotTests). Not a test itself; both run only through `Scripts/screenshots.sh`.
//

import XCTest

class ScreenshotTestCase: XCTestCase {
    var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The first sync triggers the system notification permission alert on a fresh simulator; allow it so it never
    /// covers a scene (interruption monitors only fire on a later interaction, hence the nudging taps below).
    func allowNotifications() {
        addUIInterruptionMonitor(withDescription: "Notification permission") { alert in
            for label in ["Allow", "Erlauben"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
    }

    /// Opens a sidebar section: on iPhone from the main page (the previous screen is popped first), on iPad
    /// directly from the always-visible sidebar.
    @MainActor
    func openSection(_ title: String, in app: XCUIApplication) {
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
    func waitForSyncToFinish(in app: XCUIApplication, nudge: Bool = false, timeout: TimeInterval = 300) {
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
    func goBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists { back.tap() }
    }

    @MainActor
    func containing(_ text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Full-screen capture (status bar included), kept in the result bundle under `name`; the script exports it.
    @MainActor
    func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
