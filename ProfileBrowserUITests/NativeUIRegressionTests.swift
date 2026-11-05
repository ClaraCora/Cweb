import XCTest

@MainActor
final class NativeUIRegressionTests: XCTestCase {
    private let groupID = "group.10000000-0000-0000-0000-000000000001"
    private let profileID = "profile.20000000-0000-0000-0000-000000000001"

    private func launch(dark: Bool = false, large: Bool = false, resume: Bool = false) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        // Exercise the real app appearance preference; AppleInterfaceStyle is
        // not reliably applied to a SwiftUI scene by iOS 26 test launches.
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-app.appearanceMode", dark ? "dark" : "light"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        if resume { app.launchArguments.append("-ui-test-resume") }
        app.launch()
        XCTAssertTrue(app.buttons[groupID].waitForExistence(timeout: 10))
        return app
    }

    private func selectTab(_ title: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[title]
        let target = tab.exists ? tab : app.buttons[title].firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        target.tap()
    }

    private func taskButton(_ action: String, in app: XCUIApplication) -> XCUIElement {
        let buttons = app.buttons.matching(identifier: "groupCheckIn." + action)
        XCTAssertTrue(buttons.firstMatch.waitForExistence(timeout: 5))
        // Full-screen covers can leave the presenting page in XCTest's tree.
        let visible = buttons.allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(visible, "No visible task button: " + action)
        return visible ?? buttons.firstMatch
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testNativeSurfacesLightDarkAndAccessibility() {
        for variant in [(false, false, "light"), (true, false, "dark"), (false, true, "large-type")] {
            let app = launch(dark: variant.0, large: variant.1)
            capture("groups-" + variant.2)
            app.buttons[groupID].tap()
            XCTAssertTrue(app.buttons[profileID].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons[profileID].label.contains("480"))
            XCTAssertTrue(taskButton("start", in: app).isHittable)
            for action in ["start", "pause", "stop"] {
                let control = app.buttons["groupCheckIn." + action]
                XCTAssertTrue(control.exists)
                XCTAssertGreaterThanOrEqual(control.frame.width, 44)
                XCTAssertGreaterThanOrEqual(control.frame.height, 44)
                XCTAssertLessThan(control.frame.maxY, app.frame.maxY)
            }
            capture("environments-" + variant.2)
            selectTab("代理", in: app)
            XCTAssertTrue(app.buttons["proxy.validateAll"].waitForExistence(timeout: 5))
            capture("proxies-" + variant.2)
            selectTab("设置", in: app)
            let backup = app.buttons["settings.backup"]
            for _ in 0..<5 {
                if backup.exists && backup.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(backup.waitForExistence(timeout: 5))
            XCTAssertTrue(backup.isHittable)
            capture("settings-" + variant.2)
            app.terminate()
        }
    }

    func testBrowserToolsReturnSpaceToPage() {
        let app = launch()
        app.buttons[groupID].tap()
        let profile = app.buttons[profileID]
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        // On a wide iPad row the center is blank space. It must still open
        // the environment, rather than requiring a tap directly on text.
        profile.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let web = app.webViews.firstMatch
        let showTools = app.buttons["browser.showToolbar"]
        XCTAssertTrue(web.waitForExistence(timeout: 10))
        XCTAssertTrue(showTools.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(showTools.frame.width, 44)
        XCTAssertGreaterThanOrEqual(showTools.frame.height, 44)
        let pageHeight = web.frame.height
        showTools.tap()
        let hideTools = app.buttons["browser.hideToolbar"]
        XCTAssertTrue(hideTools.waitForExistence(timeout: 5))
        XCTAssertLessThan(web.frame.height, pageHeight)
        hideTools.tap()
        XCTAssertTrue(showTools.waitForExistence(timeout: 5))
        XCTAssertEqual(web.frame.height, pageHeight, accuracy: 2)
        let fill = app.buttons["browser.fill"]
        XCTAssertGreaterThan(fill.frame.midX, app.frame.midX)
        capture("browser-tools-collapsed")
    }

    func testLandscapeSurfacesStayUsable() {
        let app = launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.buttons[groupID].isHittable)
        capture("groups-landscape")
        app.buttons[groupID].tap()
        XCTAssertTrue(taskButton("start", in: app).isHittable)
        XCTAssertTrue(app.buttons[profileID].isHittable)
        capture("environments-landscape")
        selectTab("代理", in: app)
        XCTAssertTrue(app.buttons["proxy.validateAll"].waitForExistence(timeout: 5))
        capture("proxies-landscape")
        selectTab("设置", in: app)
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        capture("settings-landscape")
    }

    func testPasswordDefaultsToSecureAndHidesAgainAfterBackground() {
        let app = launch()
        app.buttons[groupID].tap()
        app.buttons[profileID].press(forDuration: 1)
        let edit = app.buttons["编辑环境"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(app.navigationBars["编辑环境"].waitForExistence(timeout: 5))
        for _ in 0..<4 where !app.buttons["显示密码"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.secureTextFields.firstMatch.exists)
        app.buttons["显示密码"].tap()
        XCTAssertTrue(app.buttons["隐藏密码"].exists)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["显示密码"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields.firstMatch.exists)
        capture("password-reconcealed")
    }

    func testTaskControlsPreserveFillAndWebSpaceAndResumeAfterRelaunch() {
        var app = launch()
        app.buttons[groupID].tap()
        taskButton("start", in: app).tap()
        let fill = app.buttons["browser.fill"]
        XCTAssertTrue(fill.waitForExistence(timeout: 10))
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(fill.frame.midX, app.frame.midX)
        XCTAssertLessThan(fill.frame.midY, app.frame.height * 0.25)
        XCTAssertGreaterThan(web.frame.height, app.frame.height * 0.55)
        taskButton("pause", in: app).tap()
        XCTAssertTrue(taskButton("start", in: app).isEnabled)
        capture("task-paused-fill-position")
        app.terminate()
        app = launch(resume: true)
        app.buttons[groupID].tap()
        taskButton("start", in: app).tap()
        XCTAssertTrue(app.buttons["browser.fill"].waitForExistence(timeout: 10))
        taskButton("stop", in: app).tap()
        XCTAssertTrue(app.staticTexts["本组签到已停止"].waitForExistence(timeout: 5))
        capture("task-stopped")
    }
}
