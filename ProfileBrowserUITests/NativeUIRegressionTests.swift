import XCTest

@MainActor
final class NativeUIRegressionTests: XCTestCase {
    private let groupID = "group.10000000-0000-0000-0000-000000000001"
    private let profileID = "profile.20000000-0000-0000-0000-000000000001"

    private func launch(dark: Bool = false, large: Bool = false, resume: Bool = false, completed: Bool = false, appearanceOverride: Bool = true, emptyGroups: Bool = false) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        // Exercise the real app appearance preference; AppleInterfaceStyle is
        // not reliably applied to a SwiftUI scene by iOS 26 test launches.
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        if appearanceOverride { app.launchArguments += ["-app.appearanceMode", dark ? "dark" : "light"] }
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        if resume { app.launchArguments.append("-ui-test-resume") }
        if completed { app.launchArguments.append("-ui-test-completed") }
        if emptyGroups { app.launchArguments.append("-ui-test-empty-groups") }
        app.launch()
        XCTAssertTrue(app.buttons[emptyGroups ? "groups.create" : groupID].waitForExistence(timeout: 10))
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

    func testProxyRedesignAndFilters() {
        for dark in [false, true] {
            let app = launch(dark: dark)
            selectTab("代理", in: app)
            for entry in ["validateAll", "import", "add", "more", "rules", "filter.all", "filter.available", "filter.untested", "filter.unavailable"] {
                let control = app.buttons["proxy." + entry]
                XCTAssertTrue(control.waitForExistence(timeout: 5))
                XCTAssertTrue(control.isHittable)
                // UIKit sizes navigation bar items independently of custom
                // controls. Verify the app's own controls against its 44 pt floor.
                if entry != "add" && entry != "more" {
                    XCTAssertGreaterThanOrEqual(control.frame.height.rounded(), 44)
                    XCTAssertGreaterThanOrEqual(control.frame.width.rounded(), 44)
                }
            }
            capture(dark ? "proxies-redesign-dark" : "proxies-redesign-light")

            app.buttons["proxy.filter.available"].tap()
            XCTAssertTrue(app.buttons["proxy.row.1"].exists)
            XCTAssertTrue(app.buttons["proxy.row.2"].exists)
            XCTAssertTrue(app.buttons["proxy.row.3"].exists)
            XCTAssertFalse(app.buttons["proxy.row.4"].exists)
            XCTAssertEqual(app.buttons["proxy.filter.available"].value as? String, "已选择")

            app.buttons["proxy.filter.untested"].tap()
            XCTAssertTrue(app.buttons["proxy.row.4"].exists)
            XCTAssertTrue(app.buttons["proxy.row.4"].label.contains("已锁定"))
            XCTAssertFalse(app.buttons["proxy.row.1"].exists)
            capture(dark ? "proxies-filter-untested-dark" : "proxies-filter-untested-light")

            app.buttons["proxy.filter.unavailable"].tap()
            XCTAssertTrue(app.buttons["proxy.row.5"].exists)
            XCTAssertFalse(app.buttons["proxy.row.4"].exists)

            app.buttons["proxy.filter.all"].tap()
            if dark {
                XCUIDevice.shared.orientation = .landscapeLeft
                let landscapeReady = XCTNSPredicateExpectation(
                    predicate: NSPredicate { _, _ in
                        app.frame.width > app.frame.height && app.buttons["proxy.more"].isHittable
                    },
                    object: nil
                )
                wait(for: [landscapeReady], timeout: 5)
                capture("proxies-redesign-landscape")
                XCUIDevice.shared.orientation = .portrait
            }
            let search = app.searchFields.firstMatch
            let searchReady = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in
                    app.frame.width < app.frame.height && search.isHittable
                },
                object: nil
            )
            wait(for: [searchReady], timeout: 5)
            search.tap()
            search.typeText("127.0.0.2")
            XCTAssertTrue(app.buttons["proxy.row.2"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["proxy.row.1"].exists)
            capture(dark ? "proxies-search-dark" : "proxies-search-light")
            app.terminate()
        }
    }

    func testProxyActionsAndNavigation() {
        let app = launch()
        selectTab("代理", in: app)
        app.buttons["proxy.rules"].tap()
        XCTAssertTrue(app.navigationBars["测速与保留规则"].waitForExistence(timeout: 5))
        app.buttons["editor.cancel"].tap()

        app.buttons["proxy.import"].tap()
        XCTAssertTrue(app.navigationBars["导入代理"].waitForExistence(timeout: 5))
        app.buttons["关闭"].tap()

        app.buttons["proxy.add"].tap()
        XCTAssertTrue(app.navigationBars["添加代理"].waitForExistence(timeout: 5))
        app.buttons["editor.cancel"].tap()

        app.buttons["proxy.row.1"].tap()
        XCTAssertTrue(app.navigationBars["编辑代理"].waitForExistence(timeout: 5))
        app.buttons["editor.cancel"].tap()

        let locked = app.buttons["proxy.row.4"]
        let list = app.collectionViews.firstMatch
        for _ in 0..<3 where !locked.isHittable { list.swipeUp() }
        locked.swipeRight()
        XCTAssertTrue(app.buttons["解锁"].waitForExistence(timeout: 5))
        app.buttons["解锁"].tap()
        XCTAssertFalse(locked.label.contains("已锁定"))
        locked.swipeRight()
        app.buttons["锁定"].tap()
        XCTAssertTrue(locked.label.contains("已锁定"))

        app.buttons["proxy.more"].tap()
        app.buttons["批量导出"].tap()
        XCTAssertTrue(app.navigationBars["批量导出"].waitForExistence(timeout: 5))
        app.buttons["关闭"].tap()
        XCTAssertTrue(app.navigationBars["代理"].waitForExistence(timeout: 5))
        capture("proxies-actions-verified")
    }

    func testGroupRedesignLightDarkAndLandscape() {
        let secondGroupID = "group.10000000-0000-0000-0000-000000000002"
        for dark in [false, true] {
            let app = launch(dark: dark)
            XCTAssertEqual(app.staticTexts["groups.summary"].label, "2 个分组 · 6 个环境")
            for entry in ["groups.create", "groups.reorder", groupID, secondGroupID] {
                let control = app.buttons[entry]
                XCTAssertTrue(control.waitForExistence(timeout: 5))
                XCTAssertTrue(control.isHittable)
                XCTAssertGreaterThanOrEqual(control.frame.width.rounded(), 44)
                XCTAssertGreaterThanOrEqual(control.frame.height.rounded(), 44)
                XCTAssertLessThanOrEqual(control.frame.maxX, app.frame.maxX)
            }
            XCTAssertTrue(app.buttons[groupID].label.contains("5 个环境"))
            XCTAssertTrue(app.buttons[secondGroupID].label.contains("WORK-02"))
            capture(dark ? "groups-redesign-dark" : "groups-redesign-light")

            if dark {
                XCUIDevice.shared.orientation = .landscapeLeft
                let landscapeReady = XCTNSPredicateExpectation(
                    predicate: NSPredicate { _, _ in
                        app.frame.width > app.frame.height && app.buttons["groups.create"].isHittable
                    },
                    object: nil
                )
                wait(for: [landscapeReady], timeout: 5)
                XCTAssertTrue(app.buttons["groups.reorder"].isHittable)
                capture("groups-redesign-landscape")
                XCUIDevice.shared.orientation = .portrait
            }
            app.terminate()
        }
    }

    func testGroupActionsAndNavigation() {
        let app = launch()
        app.buttons["groups.create"].tap()
        XCTAssertTrue(app.navigationBars["新建环境"].waitForExistence(timeout: 5))
        app.buttons["editor.cancel"].tap()

        app.buttons["groups.reorder"].tap()
        XCTAssertTrue(app.navigationBars["分组排序"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()

        app.buttons[groupID].tap()
        XCTAssertTrue(app.buttons[profileID].waitForExistence(timeout: 5))
        app.navigationBars.buttons["分组"].tap()
        XCTAssertTrue(app.buttons[groupID].waitForExistence(timeout: 5))

        app.buttons[groupID].press(forDuration: 1)
        app.buttons["编辑分组"].tap()
        XCTAssertTrue(app.navigationBars["编辑分组"].waitForExistence(timeout: 5))
        app.buttons["editor.cancel"].tap()

        app.buttons[groupID].press(forDuration: 1)
        app.buttons["删除整个分组"].tap()
        XCTAssertTrue(app.alerts["删除整个分组？"].waitForExistence(timeout: 5))
        app.alerts.buttons["取消"].tap()
        XCTAssertTrue(app.buttons[groupID].isHittable)
        XCTAssertEqual(app.staticTexts["groups.summary"].label, "2 个分组 · 6 个环境")
        capture("groups-actions-verified")
    }

    func testEmptyGroupsCanCreate() {
        let app = launch(emptyGroups: true)
        XCTAssertEqual(app.staticTexts["groups.summary"].label, "0 个分组 · 0 个环境")
        XCTAssertTrue(app.staticTexts["还没有分组"].exists)
        XCTAssertFalse(app.buttons["groups.reorder"].isEnabled)
        capture("groups-redesign-empty")
        app.buttons["groups.create"].tap()
        XCTAssertTrue(app.navigationBars["新建环境"].waitForExistence(timeout: 5))
        app.buttons["editor.cancel"].tap()
        XCTAssertTrue(app.buttons["groups.create"].isHittable)
    }

    func testSettingsLayoutInLightDarkAndLandscape() {
        let entries = ["appearance.system", "appearance.light", "appearance.dark", "proxyPolicy", "script", "history", "backup", "about"]
        for dark in [false, true] {
            let app = launch(dark: dark)
            selectTab("设置", in: app)

            for entry in entries {
                let control = app.buttons["settings." + entry]
                XCTAssertTrue(control.waitForExistence(timeout: 5))
                XCTAssertTrue(control.isHittable, "Settings entry should be visible without scrolling: " + entry)
                XCTAssertGreaterThanOrEqual(control.frame.width.rounded(), 44)
                XCTAssertGreaterThanOrEqual(control.frame.height.rounded(), 44)
            }
            capture(dark ? "settings-redesign-dark" : "settings-redesign-light")

            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
            capture(dark ? "settings-refined-landscape-dark" : "settings-refined-landscape-light")
            let backup = app.buttons["settings.backup"]
            let list = app.scrollViews["settings.scroll"]
            XCTAssertTrue(list.waitForExistence(timeout: 5))
            for _ in 0..<5 where !backup.isHittable { list.swipeUp() }
            if !backup.isHittable {
                let hierarchy = XCTAttachment(string: app.debugDescription)
                hierarchy.name = "settings-landscape-hierarchy"
                hierarchy.lifetime = .keepAlways
                add(hierarchy)
            }
            XCTAssertTrue(backup.isHittable)
            capture(dark ? "settings-refined-landscape-bottom-dark" : "settings-refined-landscape-bottom-light")
            XCUIDevice.shared.orientation = .portrait
            app.terminate()
        }
    }

    func testSettingsAppearanceSelection() {
        // Launch arguments override UserDefaults writes. Omit the fixed theme
        // here so the actual appearance preference can change through the UI.
        let app = launch(appearanceOverride: false)
        selectTab("设置", in: app)
        for mode in ["dark", "light", "system", "light"] {
            let option = app.buttons["settings.appearance." + mode]
            option.tap()
            XCTAssertEqual(option.value as? String, "已选择")
            for other in ["system", "light", "dark"] where other != mode {
                XCTAssertEqual(app.buttons["settings.appearance." + other].value as? String, "未选择")
            }
        }
        capture("settings-appearance-selected-light")
        app.terminate()
        let relaunched = launch(appearanceOverride: false)
        selectTab("设置", in: relaunched)
        XCTAssertEqual(relaunched.buttons["settings.appearance.light"].value as? String, "已选择")
    }

    func testSettingsDestinationsAndBackupDismissal() {
        let app = launch()
        selectTab("设置", in: app)
        for (entry, title) in [("proxyPolicy", "测速与保留规则"), ("script", "签到脚本"), ("history", "签到记录"), ("about", "关于")] {
            let control = app.buttons["settings." + entry]
            let list = app.scrollViews["settings.scroll"]
            for _ in 0..<5 where !control.isHittable {
                if entry == "about" { list.swipeDown() } else { list.swipeUp() }
            }
            XCTAssertTrue(control.isHittable)
            control.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            let cancel = app.buttons["editor.cancel"]
            if cancel.exists {
                cancel.tap()
            } else {
                app.navigationBars[title].buttons.firstMatch.tap()
            }
            XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        }

        app.buttons["settings.backup"].tap()
        XCTAssertTrue(app.navigationBars["加密备份"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["导出备份密码"].exists)
        capture("settings-refined-backup-sheet")
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["settings.backup"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.backup"].isHittable)
        capture("settings-refined-backup-dismissed")
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

    func testCompletedRowsKeepStatusTextAndCompactHeight() {
        let app = launch(completed: true)
        app.buttons[groupID].tap()
        let row = app.buttons[profileID]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let context = app.staticTexts["profile.context.20000000-0000-0000-0000-000000000001"]
        XCTAssertTrue(context.waitForExistence(timeout: 5))
        XCTAssertTrue(context.label.contains("今日已完成"))
        XCTAssertTrue(context.label.contains("历史缓存"))
        // The status fits in at most a few text lines at the default size;
        // it must not stretch to fill a large part of the list row.
        XCTAssertLessThan(context.frame.height, 50)
        XCTAssertLessThan(row.frame.height, 125)
        XCTAssertGreaterThanOrEqual(row.frame.height, 44)
        capture("environments-completed-cached")
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
        XCTAssertTrue(app.buttons["groupCheckIn.startAvailable"].waitForExistence(timeout: 5))
        app.buttons["groupCheckIn.startAvailable"].tap()
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

    func testWebsiteRulePreviewAndSaveFromBrowser() {
        let app = launch()
        app.buttons[groupID].tap()
        app.buttons[profileID].tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10))
        app.buttons["browser.more"].tap()
        app.buttons["browser.websiteRules"].tap()
        XCTAssertTrue(app.navigationBars["网站识别规则"].waitForExistence(timeout: 5))
        let preview = app.buttons["测试当前页面（不执行签到）"]
        for _ in 0..<8 where !preview.isHittable { app.swipeUp() }
        XCTAssertTrue(preview.isHittable)
        preview.tap()
        XCTAssertTrue(app.staticTexts["读取金额：$42.00"].waitForExistence(timeout: 5))
        app.buttons["保存"].tap()
        let feedback = app.staticTexts["已保存，下次进入环境或新任务生效。"]
        for _ in 0..<3 where !feedback.isHittable { app.swipeUp() }
        XCTAssertTrue(feedback.waitForExistence(timeout: 5))
        capture("website-rules-preview-saved")
    }
}
