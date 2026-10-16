//
//  ManualScreenshotTests.swift
//  EngelsystemClientUITests
//
//  Every screen of the iPhone app once, for the published guide (W-07, 2026-10-16) — separate from the App Store set
//  (ScreenshotTests). Not a regression test: run it only through `Scripts/screenshots.sh manual`, which prepares a clean
//  simulator and exports the attachments to Screenshots/manual/iphone/en/NN-<name>.png. All data is Demo Mode. A scene
//  whose screen cannot be reached is skipped (recorded as an activity) instead of ending the run; the script lists what
//  was captured. A new screen needs a new scene here (see docs/testing.md).
//

import XCTest

final class ManualScreenshotTests: ScreenshotTestCase {
    private var app: XCUIApplication!
    private var counter = 0

    override func setUpWithError() throws {
        try super.setUpWithError()
        // A failing step in one scene must not end the run: the scene is skipped, the next one starts from the main page.
        continueAfterFailure = true
    }

    // MARK: - Scenes

    /// One instance: the main page, every area, every Settings page.
    @MainActor
    func testSingleInstanceScreens() throws {
        allowNotifications()
        launch(extra: [])
        shot("main-page")

        scene("shifts") {
            self.open("Shifts")
            self.waitFor(self.shiftRow("Info Desk Shift"))
            self.shot("shifts")
            if self.app.buttons["shiftFilterMenu"].exists {
                self.app.buttons["shiftFilterMenu"].tap()
                if self.app.buttons["Upcoming"].waitForExistence(timeout: 3) { self.shot("shifts-filter-and-sort-menu") }
                self.dismissMenu()
            }
            let registration = self.app.buttons.matching(identifier: "shiftRow")
                .matching(NSPredicate(format: "label CONTAINS %@", "Registration Desk")).firstMatch
            if registration.waitForExistence(timeout: 5) {
                registration.tap()
                if self.app.navigationBars["Registration Desk"].waitForExistence(timeout: 5) { self.shot("shift-detail") }
                self.goBack(self.app)
            }
            let heaven = self.app.buttons["Heaven"].firstMatch
            if heaven.waitForExistence(timeout: 3) {
                heaven.tap()
                if self.app.navigationBars["Heaven"].waitForExistence(timeout: 5) { self.shot("location-detail-from-shift") }
            }
        }

        scene("news") {
            self.open("News")
            self.waitFor(self.app.staticTexts["Welcome to the Demo Congress!"])
            self.shot("news")
            let readMore = self.app.buttons["Read More"].firstMatch
            if readMore.waitForExistence(timeout: 3) {
                readMore.tap()
                _ = self.app.buttons["Show Less"].waitForExistence(timeout: 3)
                self.shot("news-expanded")
                self.app.buttons["Show Less"].firstMatch.tap()
            }
            let comments = self.app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'comment'")).firstMatch
            if comments.waitForExistence(timeout: 3) {
                comments.tap()
                _ = self.app.navigationBars.count
                self.shot("news-comments")
            }
        }

        scene("profile") {
            self.open("Profile")
            self.waitFor(self.app.staticTexts["Engel"])
            self.shot("profile")
        }

        scene("locations") {
            self.open("Locations")
            self.waitFor(self.containing("Chill Space", in: self.app))
            self.shot("locations")
            let chill = self.containing("Chill Space", in: self.app)
            if chill.exists {
                chill.tap()
                if self.app.navigationBars["Chill Space"].waitForExistence(timeout: 5) { self.shot("location-detail") }
            }
        }

        scene("messages") {
            self.open("Messages")
            let conversation = self.containing("Helper Angel", in: self.app)
            self.waitFor(conversation)
            self.shot("messages")
            if conversation.exists {
                conversation.tap()
                _ = self.app.staticTexts["Could you cover my shift tomorrow?"].waitForExistence(timeout: 5)
                self.shot("conversation")
                self.goBack(self.app)
            }
            let new = self.app.buttons["New Message"]
            if new.waitForExistence(timeout: 3) {
                new.tap()
                _ = self.containing("Helper Angel", in: self.app).waitForExistence(timeout: 10)
                self.shot("new-message")
                self.app.buttons["Cancel"].firstMatch.tap()
            }
        }

        scene("settings-hub") {
            self.openSettings()
            self.shot("settings")
        }

        scene("settings-instances") {
            self.openSettings()
            guard self.openSettingsPage("Instances") else { return }
            self.shot("settings-instances")
            let demo = self.app.staticTexts["Demo"].firstMatch
            if demo.waitForExistence(timeout: 5) {
                demo.tap()
                _ = self.app.staticTexts["featuresSummary"].waitForExistence(timeout: 5)
                self.shot("instance-page")
                let summary = self.app.staticTexts["featuresSummary"]
                if summary.exists {
                    summary.tap()
                    self.shot("instance-features")
                }
                self.app.swipeUp()
                self.shot("instance-page-more")
                self.goBack(self.app)
            }
            let add = self.app.buttons["Add Instance"]
            if add.waitForExistence(timeout: 3) {
                add.tap()
                if self.app.textFields["Name (e.g. 42C3)"].waitForExistence(timeout: 5) { self.shot("add-instance") }
                self.app.buttons["Cancel"].firstMatch.tap()
            }
        }

        for page in ["Notifications", "Sync", "Phone Numbers", "Privacy", "About"] {
            scene("settings-\(page)") {
                self.openSettings()
                guard self.openSettingsPage(page) else { return }
                self.shot("settings-" + page.lowercased().replacingOccurrences(of: " ", with: "-"))
            }
        }

        scene("settings-diagnostics") {
            self.openSettings()
            guard self.openSettingsPage("Diagnostics") else { return }
            self.shot("settings-diagnostics")
            let export = self.app.buttons["Export Diagnostics"]
            if export.waitForExistence(timeout: 3) {
                export.tap()
                if self.app.navigationBars["Export Diagnostics"].waitForExistence(timeout: 5) { self.shot("export-diagnostics") }
                self.app.buttons["Cancel"].firstMatch.tap()
            }
            let log = self.app.buttons["View Debug Log"]
            if log.waitForExistence(timeout: 3) {
                log.tap()
                if self.app.navigationBars["Debug Log"].waitForExistence(timeout: 5) { self.shot("debug-log") }
            }
        }
    }

    /// Two instances: the Instances page, then Shifts and Locations in "Sectioned" and in "Merged" mode.
    @MainActor
    func testMultiInstanceScreens() throws {
        counter = 60 // after the single-instance scenes, so the two tests' file names never collide
        allowNotifications()
        launch(extra: ["-multiInstanceDisplayMode", "sectioned"])
        scene("second-instance") {
            self.openSettings()
            guard self.openSettingsPage("Instances") else { return }
            self.addDemoInstance(named: "Congress", address: "demo://congress.local")
            self.shot("settings-instances-two")
            self.home()
        }
        for mode in ["sectioned", "merged"] {
            scene("shifts-\(mode)") {
                if mode == "merged" { self.relaunch(extra: ["-multiInstanceDisplayMode", "merged"]) }
                self.open("Shifts")
                self.waitFor(self.shiftRow("Info Desk Shift"))
                self.shot("shifts-\(mode)")
            }
            scene("locations-\(mode)") {
                self.open("Locations")
                self.waitFor(self.containing("Chill Space", in: self.app))
                self.shot("locations-\(mode)")
            }
            scene("news-\(mode)") {
                self.open("News")
                self.waitFor(self.app.staticTexts["Welcome to the Demo Congress!"])
                self.shot("news-\(mode)")
            }
        }
        scene("main-page-two") {
            self.home()
            self.shot("main-page-two-instances")
        }
    }

    // MARK: - Steps

    /// Runs one scene; whatever state it leaves behind, the next scene starts from the main page.
    @MainActor
    private func scene(_ name: String, _ body: () -> Void) {
        XCTContext.runActivity(named: "scene \(name)") { _ in
            home()
            body()
        }
    }

    @MainActor
    private func launch(extra: [String], reset: Bool = true) {
        app = XCUIApplication()
        // Saved instances of an earlier run are deleted first (not on a relaunch inside a test: that keeps the second instance).
        if reset { app.launchArguments += ["-reset-instances"] }
        app.launchArguments += ["-seed-demo-instance", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-mainViewLastSelectedSection", "none"] + extra
        app.launch()
        XCTAssertTrue(app.staticTexts["Shifts"].waitForExistence(timeout: 30))
        waitForSyncToFinish(in: app, nudge: true)
        waitUntilSynced()
    }

    /// With the saved instances reset, the first sync may not have started yet when the banner check passes: wait
    /// until the main page no longer says "Not synced yet" (tapping it refreshes) and the Messages row (shown once the
    /// capability probe finished) is there.
    @MainActor
    private func waitUntilSynced() {
        let notSynced = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Not synced yet")).firstMatch
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline && (notSynced.exists || !app.staticTexts["Messages"].exists) {
            if notSynced.exists && notSynced.isHittable { notSynced.tap() }
            waitForSyncToFinish(in: app)
            Thread.sleep(forTimeInterval: 3)
        }
    }

    @MainActor
    private func relaunch(extra: [String]) {
        app.terminate()
        launch(extra: extra, reset: false)
    }

    /// Takes the next numbered screenshot (the number keeps the guide's order).
    @MainActor
    private func shot(_ name: String) {
        counter += 1
        Thread.sleep(forTimeInterval: 0.8) // lets transitions and list animations settle
        capture(String(format: "%02d-%@", counter, name))
    }

    /// Goes back to the main page: closes a sheet or menu, then pops until the sidebar rows are visible.
    @MainActor
    private func home() {
        for _ in 0..<8 {
            dismissMenu()
            let cancel = app.buttons["Cancel"].firstMatch
            if cancel.exists && cancel.isHittable { cancel.tap(); continue }
            // The main page is the root: no back button. (The sidebar rows' titles also appear as navigation
            // titles inside the areas, so their presence says nothing.)
            let back = app.buttons["BackButton"].firstMatch
            guard back.exists && back.isHittable else { break }
            // The bar of a page that is just being popped still shows its back button for a moment: let it finish.
            Thread.sleep(forTimeInterval: 0.8)
            guard back.exists && back.isHittable else { continue }
            back.tap()
            Thread.sleep(forTimeInterval: 0.8)
        }
        _ = app.staticTexts["Shifts"].waitForExistence(timeout: 5)
    }

    @MainActor
    private func open(_ section: String) {
        home()
        let row = app.staticTexts[section]
        guard row.waitForExistence(timeout: 10) else { return }
        row.tap()
        _ = app.navigationBars[section].waitForExistence(timeout: 10)
        waitForSyncToFinish(in: app)
    }

    @MainActor
    private func openSettings() {
        home()
        let settings = app.buttons["Settings"]
        if settings.waitForExistence(timeout: 5) { settings.tap() }
        _ = app.navigationBars["Settings"].waitForExistence(timeout: 5)
    }

    @MainActor
    private func openSettingsPage(_ title: String) -> Bool {
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        guard row.waitForExistence(timeout: 5) else { return false }
        row.tap()
        return app.navigationBars[title].waitForExistence(timeout: 5)
    }

    @MainActor
    private func dismissMenu() {
        // A tap on the top-left corner closes an open menu without choosing anything.
        if app.buttons["Upcoming"].exists || app.buttons["Earliest First"].exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).tap()
        }
    }

    @MainActor
    private func shiftRow(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    @MainActor
    private func waitFor(_ element: XCUIElement) {
        _ = element.waitForExistence(timeout: 10)
    }

    /// Adds a demo instance on the Instances page (same steps as the regression test).
    @MainActor
    private func addDemoInstance(named name: String, address: String) {
        let add = app.buttons["Add Instance"]
        guard add.waitForExistence(timeout: 5) else { return }
        let nameField = app.textFields["Name (e.g. 42C3)"]
        for _ in 0..<3 {
            add.tap()
            if nameField.waitForExistence(timeout: 4) { break }
        }
        guard nameField.exists else { return }
        nameField.tap()
        nameField.typeText(name)
        let server = app.textFields["https://engelsystem.example.org"]
        server.tap()
        server.typeText(address)
        app.buttons["Test Connection"].tap()
        _ = app.staticTexts["Connection Verified"].waitForExistence(timeout: 10)
        app.buttons["Save"].tap()
        _ = app.navigationBars["Instances"].waitForExistence(timeout: 10)
    }
}
