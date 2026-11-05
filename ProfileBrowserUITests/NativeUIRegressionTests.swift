import XCTest

@MainActor
final class NativeUIRegressionTests: XCTestCase {
    private let groupID = "group.10000000-0000-0000-0000-000000000001"
    private let profileID = "profile.20000000-0000-0000-0000-000000000001"

    private func launch(dark: Bool = false, large: Bool = false, resume: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-AppleInterfaceStyle", dark ? "Dark" : "Light"]
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
            capture("environments-" + variant.2)
            selectTab("代理", in: app)
            XCTAssertTrue(app.buttons["proxy.validateAll"].waitForExistence(timeout: 5))
            capture("proxies-" + variant.2)
            selectTab("设置", in: app)
            let backup = app.buttons["加密备份"]
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
