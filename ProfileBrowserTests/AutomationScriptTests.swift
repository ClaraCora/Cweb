import Foundation
import CoreGraphics
import CoreText
import ImageIO
import Testing
import UniformTypeIdentifiers
import WebKit
@testable import ProfileBrowser

struct AutomationScriptTests {
    @Test
    func parserExtractsMetadataAndLeavesExecutableSource() {
        let parsed = AutomationScriptParser.parse(
            """
            // ==UserScript==
            // @match https://example.com/*
            // @run-at document-start
            // ==/UserScript==
            window.CwebCheckIn?.success(\"ok\");
            """
        )

        #expect(parsed.matches == ["https://example.com/*"])
        #expect(parsed.runsAtDocumentStart)
        #expect(parsed.source.contains("window.CwebCheckIn"))
        #expect(!parsed.source.contains("@match"))
    }

    @Test
    func builderAddsMatchGuardAndDailyCompletionGate() {
        let source = AutomationScriptBuilder.build(
            code: "window.CwebCheckIn.success('ok');",
            matches: ["https://example.com/*"],
            completionKey: "cweb.checkIn.test"
        )

        #expect(source.contains("https://example.com/*"))
        #expect(source.contains("cweb.checkIn.test"))
        #expect(source.contains("localStorage.setItem"))
        #expect(source.contains("window.CwebCheckIn.success"))
    }

    @Test
    func builderIncludesCaptchaFillBridge() {
        let source = AutomationScriptBuilder.build(
            code: "window.CwebCheckIn.captchaDetected('captcha');",
            matches: ["https://example.com/*"]
        )

        #expect(source.contains("fillCaptcha"))
        #expect(source.contains("__cwebResolveCaptchaInput"))
        #expect(source.contains("candidates.find(__cwebIsVisible)"))
        #expect(source.contains("HTMLInputElement.prototype"))
        #expect(source.contains("input.value !== value"))
        #expect(source.contains("details = null"))
        #expect(source.contains("payload.captcha"))
    }

    @Test
    @MainActor
    func captchaFillCallUpdatesTheVisibleFormAndReturnsItsResult() async throws {
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = .nonPersistent()
        let page = WebPage(configuration: configuration)
        let fixture = """
        <html><body>
        <input hidden id="old" placeholder="请输入验证码">
        <form><input id="current" placeholder="请输入验证码"><button>确认</button></form>
        <script>
        window.fixtureState = { value: '', input: 0, change: 0, submits: 0 };
        document.addEventListener('input', event => {
            window.fixtureState.value = event.target.value;
            window.fixtureState.input++;
        });
        document.addEventListener('change', () => window.fixtureState.change++);
        document.querySelector('form').addEventListener('submit', event => {
            event.preventDefault(); window.fixtureState.submits++;
        });
        </script></body></html>
        """
        let fixtureURL = try #require(URL(string: "https://captcha.example.invalid"))
        for try await _ in page.load(html: fixture, baseURL: fixtureURL) { }
        let rule = WebsiteRule(host: "captcha.example.invalid", captchaInputSelector: "input[placeholder=\"请输入验证码\"]")
        _ = try await page.callJavaScript(AutomationScriptBuilder.build(
            code: "", matches: ["<all_urls>"], siteRules: [rule]
        ))

        let result = try await page.callJavaScript(
            AutomationScriptBuilder.captchaFillCall, arguments: ["code": "2746"], contentWorld: .page
        ) as? Bool
        #expect(result == true)
        let state = try #require(try await page.callJavaScript("""
        return { ...window.fixtureState,
            current: document.querySelector('#current').value,
            old: document.querySelector('#old').value };
        """) as? [String: Any])
        #expect(state["current"] as? String == "2746")
        #expect(state["value"] as? String == "2746")
        #expect(state["old"] as? String == "")
        #expect(state["input"] as? Int == 1)
        #expect(state["change"] as? Int == 1)
        #expect(state["submits"] as? Int == 0)

        _ = try await page.callJavaScript("""
        const previous = document.querySelector('#current');
        previous.id = 'replaced'; previous.hidden = true;
        const input = document.createElement('input');
        input.id = 'current'; input.placeholder = '请输入验证码';
        previous.after(input);
        """)
        let replacementResult = try await page.callJavaScript(
            AutomationScriptBuilder.captchaFillCall, arguments: ["code": "5832"], contentWorld: .page
        ) as? Bool
        #expect(replacementResult == false)
        #expect(try await page.callJavaScript("return document.querySelector('#current').value;") as? String == "")
        _ = try await page.callJavaScript("""
        window.CwebCheckIn.captureCaptcha = () => {};
        window.CwebCheckIn.retryCaptcha();
        """)
        let retriedResult = try await page.callJavaScript(
            AutomationScriptBuilder.captchaFillCall, arguments: ["code": "5832"], contentWorld: .page
        ) as? Bool
        #expect(retriedResult == true)
        #expect(try await page.callJavaScript("return document.querySelector('#current').value;") as? String == "5832")
        #expect(try await page.callJavaScript("return document.querySelector('#replaced').value;") as? String == "2746")

        _ = try await page.callJavaScript("document.querySelector('#current').hidden = true;")
        let hiddenResult = try await page.callJavaScript(
            AutomationScriptBuilder.captchaFillCall, arguments: ["code": "9317"], contentWorld: .page
        ) as? Bool
        #expect(hiddenResult == false)
        #expect(try await page.callJavaScript("return document.querySelector('#current').value;") as? String == "5832")
        #expect(try await page.callJavaScript("return window.fixtureState.submits;") as? Int == 0)
        page.stopLoading()
    }

    @Test
    func builderDetectsAccessibleCaptchaLabels() {
        let source = GlobalScriptSettings.default.source

        #expect(source.contains("[alt*=\"验证码\" i]"))
        #expect(source.contains("[placeholder*=\"验证码\" i]"))
        #expect(source.contains("[aria-label*=\"captcha\" i]"))
    }

    @Test
    func websiteRuleDecodesOldSavedDataWithCaptchaDefaults() throws {
        let data = Data("{\"host\":\"example.com\",\"balanceSelector\":\"#balance\"}".utf8)
        let rule = try JSONDecoder().decode(WebsiteRule.self, from: data)

        #expect(rule.host == "example.com")
        #expect(rule.balanceSelector == "#balance")
        #expect(!rule.captchaAutoFillEnabled)
        #expect(!rule.captchaAutoSubmitEnabled)
        #expect(rule.captchaImageSelector == nil)
        #expect(rule.captchaInputSelector == nil)
        let legacySubmitRule = try JSONDecoder().decode(WebsiteRule.self, from: Data(
            ##"{"host":"example.com","captchaAutoFillEnabled":true,"captchaSubmitSelector":"#submit"}"##.utf8
        ))
        #expect(!legacySubmitRule.captchaAutoSubmitEnabled)
        var enabledRule = legacySubmitRule
        enabledRule.captchaAutoSubmitEnabled = true
        #expect(try JSONDecoder().decode(WebsiteRule.self, from: JSONEncoder().encode(enabledRule)) == enabledRule)
    }

    @Test
    func websiteRuleMatchesLoginAndRedirectSubdomains() {
        let rule = WebsiteRule(host: "cf.sheapi.cc", captchaAutoFillEnabled: true)
        #expect(rule.matches(host: "cf.sheapi.cc"))
        #expect(rule.matches(host: "www.sheapi.cc"))
        #expect(rule.matches(host: "sheapi.cc"))
        #expect(!rule.matches(host: "example.cc"))
    }

    @Test
    func captchaOCRRejectsInvalidImageWithoutNetworkFallback() async {
        let result = await CaptchaOCRService().recognize(imageData: Data(), expectedLength: 4)
        #expect(result == .unavailable("无法读取验证码图片"))
    }

    @Test
    func captchaOCRRecognizesClearNumericImageLocally() async throws {
        let imageData = try #require(Self.syntheticCaptchaImage())
        let result = await CaptchaOCRService().recognize(imageData: imageData, expectedLength: 4)

        guard case let .recognized(code, confidence) = result else {
            Issue.record("清晰数字验证码未被本地 Vision 识别：\(result)")
            return
        }
        #expect(code == "2746")
        #expect(confidence >= 0.80)
    }

    @Test
    @MainActor
    func iOSWebKitRecognizesAndFillsCaptchaWithoutExplicitSelectors() async throws {
        let session = BrowserSession(profile: BrowserProfile(
            name: "验证码端到端回归",
            homePage: URL(string: "https://captcha.example.invalid/sign-in")!
        ))
        defer { session.close() }

        let rule = WebsiteRule(host: "captcha.example.invalid", captchaAutoFillEnabled: true)
        session.configureAutomation(
            settings: GlobalScriptSettings(
                enabled: true,
                source: GlobalScriptSettings.default.source,
                updatedAt: .now,
                siteRules: [rule]
            ),
            shouldRunToday: true,
            completionKey: "cweb.captcha.integration.\(UUID().uuidString)"
        )

        let html = """
        <html><body>
        <div class="captcha">
            <canvas aria-label="Captcha image" width="240" height="80"></canvas>
            <label for="captcha-code">Captcha</label>
            <input id="captcha-code" placeholder="Enter captcha" autocomplete="off">
        </div>
        <script>
        const canvas = document.querySelector('canvas');
        const context = canvas.getContext('2d');
        context.fillStyle = '#fff';
        context.fillRect(0, 0, canvas.width, canvas.height);
        context.fillStyle = '#000';
        context.font = 'bold 56px Helvetica';
        context.fillText('2746', 36, 62);
        document.querySelector('#captcha-code').addEventListener('input', () => {
            document.querySelector('.captcha').hidden = true;
        });
        </script>
        </body></html>
        """
        for try await _ in session.page.load(
            html: html,
            baseURL: URL(string: "https://captcha.example.invalid/sign-in")!
        ) { }

        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        var filled = false
        while ContinuousClock.now < deadline {
            let value = try? await session.page.callJavaScript(
                "return document.querySelector('#captcha-code')?.value || '';"
            ) as? String
            if value == "2746" {
                filled = true
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(filled)
        #expect(try await session.page.callJavaScript(
            "return document.querySelector('.captcha')?.hidden === true;"
        ) as? Bool == true)
        #expect(try await session.page.callJavaScript(
            "return window.__cwebCaptchaSubmitCount || 0;"
        ) as? Int == 0)
    }

    @Test
    @MainActor
    func iOSWebKitRecognizesAndFillsSheApiStyleDataImageCaptcha() async throws {
        let session = BrowserSession(profile: BrowserProfile(
            name: "SheApi 图片验证码端到端回归",
            homePage: URL(string: "https://cf.sheapi.cc/sign-in")!
        ))
        defer { session.close() }

        let imageData = try #require(Self.syntheticCaptchaImage())
        let imageURI = "data:image/png;base64,\(imageData.base64EncodedString())"
        let rule = WebsiteRule(
            host: "cf.sheapi.cc",
            captchaAutoFillEnabled: true,
            captchaImageSelector: "img[alt=\"验证码图片\"]",
            captchaInputSelector: "input[placeholder=\"请输入验证码\"]",
            captchaExpectedLength: 4
        )
        session.configureAutomation(
            settings: GlobalScriptSettings(
                enabled: true,
                source: GlobalScriptSettings.default.source,
                updatedAt: .now,
                siteRules: [rule]
            ),
            shouldRunToday: true,
            completionKey: "cweb.captcha.image.integration.\(UUID().uuidString)"
        )

        let html = """
        <html><body>
        <div class="captcha">
            <img alt="验证码图片" src="\(imageURI)">
            <input placeholder="请输入验证码" autocomplete="off">
        </div>
        <script>
        window.fixtureState = { value: '', input: 0, change: 0 };
        const input = document.querySelector('input[placeholder="请输入验证码"]');
        input.addEventListener('input', () => {
            window.fixtureState.value = input.value;
            window.fixtureState.input++;
        });
        input.addEventListener('change', () => window.fixtureState.change++);
        </script>
        </body></html>
        """
        for try await _ in session.page.load(
            html: html,
            // The login page uses cf.sheapi.cc, while the authenticated
            // profile page redirects to www.sheapi.cc.
            baseURL: URL(string: "https://www.sheapi.cc/profile")!
        ) { }

        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        var value = ""
        while ContinuousClock.now < deadline {
            value = (try? await session.page.callJavaScript(
                "return document.querySelector('input[placeholder=\"请输入验证码\"]')?.value || '';"
            ) as? String) ?? ""
            if value == "2746" { break }
            try await Task.sleep(for: .milliseconds(100))
        }

        #expect(value == "2746")
        #expect(try await session.page.callJavaScript("return window.fixtureState.value;") as? String == "2746")
        #expect(try await session.page.callJavaScript("return window.fixtureState.input;") as? Int == 1)
        #expect(try await session.page.callJavaScript("return window.fixtureState.change;") as? Int == 1)
    }

    @Test
    @MainActor
    func iOSWebKitRecognizesCaptchaAppearingAfterCheckInClickOnRedirectHost() async throws {
        let session = BrowserSession(profile: BrowserProfile(
            name: "SheApi 签到弹窗时序回归",
            homePage: URL(string: "https://cf.sheapi.cc/sign-in")!
        ))
        defer { session.close() }

        let imageData = try #require(Self.syntheticCaptchaImage())
        let imageURI = "data:image/png;base64,\(imageData.base64EncodedString())"
        let rule = WebsiteRule(
            host: "cf.sheapi.cc",
            captchaAutoFillEnabled: true,
            captchaImageSelector: "img[alt=\"验证码图片\"]",
            captchaInputSelector: "input[placeholder=\"请输入验证码\"]",
            captchaExpectedLength: 4
        )
        session.configureAutomation(
            settings: GlobalScriptSettings(
                enabled: true,
                source: GlobalScriptSettings.default.source,
                updatedAt: .now,
                siteRules: [rule]
            ),
            shouldRunToday: true,
            completionKey: "cweb.captcha.dynamic.integration.\(UUID().uuidString)"
        )

        let html = """
        <html><body>
        <button id="check-in">立即签到</button>
        <div id="dialog" role="dialog" hidden>
            <img alt="验证码图片" src="\(imageURI)">
            <input placeholder="请输入验证码" autocomplete="off">
            <button type="button">取消</button>
        </div>
        <script>
        window.fixtureState = { opened: 0, value: '', input: 0 };
        document.querySelector('#check-in').addEventListener('click', () => {
            document.querySelector('#dialog').hidden = false;
            window.fixtureState.opened++;
        });
        document.querySelector('#dialog input').addEventListener('input', event => {
            window.fixtureState.value = event.target.value;
            window.fixtureState.input++;
        });
        </script>
        </body></html>
        """
        for try await _ in session.page.load(
            html: html,
            baseURL: URL(string: "https://www.sheapi.cc/profile")!
        ) { }

        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        var value = ""
        while ContinuousClock.now < deadline {
            value = (try? await session.page.callJavaScript(
                "return document.querySelector('#dialog input')?.value || '';"
            ) as? String) ?? ""
            if value == "2746" { break }
            try await Task.sleep(for: .milliseconds(100))
        }

        #expect(value == "2746")
        #expect(try await session.page.callJavaScript("return window.fixtureState.opened;") as? Int == 1)
        #expect(try await session.page.callJavaScript("return window.fixtureState.value;") as? String == "2746")
        #expect(try await session.page.callJavaScript("return window.fixtureState.input;") as? Int == 1)
        #expect(try await session.page.callJavaScript("return document.querySelector('#dialog').hidden;") as? Bool == false)
    }

    @Test(arguments: [false, true])
    @MainActor
    func captchaFillsOnceAndWaitsForExplicitRetryOrContinue(autoSubmit: Bool) async throws {
        let url = URL(string: "https://captcha.example.invalid/profile")!
        let session = BrowserSession(profile: BrowserProfile(name: "单次验证码回归", homePage: url))
        defer { session.close() }
        let image = try #require(Self.syntheticCaptchaImage())
        let rule = WebsiteRule(host: "captcha.example.invalid", captchaAutoFillEnabled: true,
            captchaAutoSubmitEnabled: autoSubmit, captchaInputSelector: "#code",
            captchaSubmitSelector: "#confirm", captchaExpectedLength: 4)
        session.configureAutomation(settings: GlobalScriptSettings(enabled: true,
            source: GlobalScriptSettings.default.source, updatedAt: .now, siteRules: [rule]),
            shouldRunToday: true, completionKey: UUID().uuidString)
        let html = """
        <html><body><div class="captcha">
            <img alt="验证码图片" src="data:image/png;base64,\(image.base64EncodedString())">
            <input id="code" placeholder="请输入验证码">
            <button id="confirm" type="button">确认</button>
        </div><script>
        window.fixtureState = { input: 0, submits: 0 };
        document.querySelector('#code').addEventListener('input', () => window.fixtureState.input++);
        document.querySelector('#confirm').addEventListener('click', () => window.fixtureState.submits++);
        </script></body></html>
        """
        for try await _ in session.page.load(html: html, baseURL: url) { }
        await waitForCaptcha(session, state: autoSubmit ? .submitted : .filled)
        let originalChallenge = try #require(session.captchaChallenge)
        #expect(session.automationState == .captcha)
        #expect(try await session.page.callJavaScript("return document.querySelector('#code').value;") as? String == "2746")
        #expect(try await session.page.callJavaScript("return window.CwebCheckIn.isPaused();") as? Bool == true)

        for _ in 0..<3 { await session.recheckAutomation() }
        session.receiveAutomationMessage(type: "captcha", message: "重复挑战", captcha: originalChallenge)
        session.receiveAutomationMessage(type: "error", message: "旧提交计时器")
        _ = try await session.page.callJavaScript("""
        document.querySelector('#code').setAttribute('data-change', 'mutation');
        window.dispatchEvent(new Event('cwebAutomationRecheck'));
        """)
        try await Task.sleep(for: .milliseconds(400))
        let duplicate = try await session.page.callJavaScript(
            AutomationScriptBuilder.captchaFillCall, arguments: ["code": "9999"]
        ) as? Bool
        #expect(duplicate == false)
        #expect(session.automationState == .captcha)
        #expect(try await session.page.callJavaScript("return window.fixtureState.input;") as? Int == 1)
        #expect(try await session.page.callJavaScript("return window.fixtureState.submits;") as? Int == (autoSubmit ? 1 : 0))

        // Even an explicit continue must not recognize the same visible image
        // again. It pauses for the user to complete verification on the page.
        await session.resumeAutomation()
        let pauseDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        while session.automationState != .captcha, ContinuousClock.now < pauseDeadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(session.automationState == .captcha)
        #expect(try await session.page.callJavaScript("return window.fixtureState.input;") as? Int == 1)

        let refreshedImage = try #require(Self.syntheticCaptchaImage(code: "5832"))
        _ = try await session.page.callJavaScript("""
        document.querySelector('img').src = imageURI;
        document.querySelector('#code').value = '';
        """, arguments: ["imageURI": "data:image/png;base64,\(refreshedImage.base64EncodedString())"])
        session.retryCaptchaRecognition()
        await waitForCaptcha(session, state: autoSubmit ? .submitted : .filled)
        #expect(try await session.page.callJavaScript("return document.querySelector('#code').value;") as? String == "5832")
        #expect(try await session.page.callJavaScript("return window.fixtureState.input;") as? Int == 2)
        #expect(try await session.page.callJavaScript("return window.fixtureState.submits;") as? Int == (autoSubmit ? 2 : 0))

        // Page changes alone do not resume detection. Only the button's native
        // resume call may accept the completion and advance the queue.
        _ = try await session.page.callJavaScript("""
        document.querySelector('.captcha').hidden = true;
        const result = document.createElement('p'); result.textContent = '今天已完成签到';
        document.body.append(result);
        """)
        await session.recheckAutomation()
        #expect(session.automationState == .captcha)
        await session.resumeAutomation()
        let successDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        while session.automationState != .success, ContinuousClock.now < successDeadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(session.automationState == .success)
    }

    @Test(arguments: ["", "#missing", "#disabled", "#hidden"])
    @MainActor
    func autoSubmitRequiresAnAvailableExplicitControl(selector: String) async throws {
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = .nonPersistent()
        let page = WebPage(configuration: configuration)
        let html = """
        <html><body><input id="code"><button id="disabled" disabled>确认</button>
        <button id="hidden" hidden>确认</button>
        <script>window.clicks = 0; document.addEventListener('click', () => window.clicks++);</script>
        </body></html>
        """
        for try await _ in page.load(html: html, baseURL: URL(string: "https://captcha.example.invalid")!) { }
        let rule = WebsiteRule(host: "captcha.example.invalid", captchaAutoFillEnabled: true,
            captchaAutoSubmitEnabled: true, captchaInputSelector: "#code", captchaSubmitSelector: selector)
        _ = try await page.callJavaScript(AutomationScriptBuilder.build(code: "", matches: ["<all_urls>"], siteRules: [rule]))
        #expect(try await page.callJavaScript(AutomationScriptBuilder.captchaFillCall, arguments: ["code": "2746"]) as? Bool == true)
        #expect(try await page.callJavaScript("return window.clicks;") as? Int == 0)
        #expect(try await page.callJavaScript("return window.CwebCheckIn.hasSubmittedCaptcha();") as? Bool == false)
    }

    @Test
    @MainActor
    func captchaPauseSurvivesANewOriginUntilExplicitContinue() async throws {
        let home = URL(string: "https://cf.example.invalid/profile")!
        let destination = URL(string: "https://www.example.invalid/profile")!
        let session = BrowserSession(profile: BrowserProfile(name: "验证码跳转暂停回归", homePage: home))
        defer { session.close() }
        session.configureAutomation(settings: GlobalScriptSettings(enabled: true,
            source: GlobalScriptSettings.default.source, updatedAt: .now,
            siteRules: [WebsiteRule(host: "cf.example.invalid")]), shouldRunToday: true,
            completionKey: UUID().uuidString)
        session.receiveAutomationMessage(type: "captcha", message: "等待验证码")
        let html = """
        <html><body><button>立即签到</button><script>
        window.clicks = 0; document.querySelector('button').onclick = () => window.clicks++;
        </script></body></html>
        """
        for try await _ in session.page.load(html: html, baseURL: destination) { }
        await session.recheckAutomation()
        #expect(try await session.page.callJavaScript("return window.CwebCheckIn.isPaused();") as? Bool == true)
        #expect(try await session.page.callJavaScript("return window.clicks;") as? Int == 0)
        #expect(session.automationState == .captcha)
        await session.resumeAutomation()
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        var clicks = 0
        while clicks == 0, ContinuousClock.now < deadline {
            clicks = (try? await session.page.callJavaScript("return window.clicks;") as? Int) ?? 0
            if clicks == 0 { try await Task.sleep(for: .milliseconds(25)) }
        }
        #expect(clicks == 1)
    }

    @Test
    @MainActor
    func staleDocumentCannotReceiveOCRFill() async throws {
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = .nonPersistent()
        let page = WebPage(configuration: configuration)
        for try await _ in page.load(html: "<html><body><input id='code'></body></html>", baseURL: URL(string: "https://captcha.example.invalid")!) { }
        _ = try await page.callJavaScript("window.__cwebDocumentID = 'new-document';")
        let rule = WebsiteRule(host: "captcha.example.invalid", captchaInputSelector: "#code")
        _ = try await page.callJavaScript(AutomationScriptBuilder.build(code: "", matches: ["<all_urls>"], siteRules: [rule]))
        #expect(try await page.callJavaScript(AutomationScriptBuilder.captchaFillCall,
            arguments: ["code": "2746", "documentID": "old-document"]) as? Bool == false)
        #expect(try await page.callJavaScript("return document.querySelector('#code').value;") as? String == "")
    }

    @MainActor
    private func waitForCaptcha(_ session: BrowserSession, state: CaptchaRecognitionState) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while session.captchaRecognitionState != state, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(25))
        }
        #expect(session.captchaRecognitionState == state)
    }

    private static func syntheticCaptchaImage(code: String = "2746") -> Data? {
        let width = 240
        let height = 80
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 56, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: code, attributes: attributes)
        )
        let bounds = CTLineGetBoundsWithOptions(line, [])
        context.textPosition = CGPoint(
            x: (CGFloat(width) - bounds.width) / 2,
            y: 10
        )
        CTLineDraw(line, context)

        guard let image = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    @Test
    func originalBundledTemplateUpgradesWithoutChangingEnabledState() throws {
        for enabled in [false, true] {
            for bundledSource in [Self.originalBundledSource, Self.previousBundledSource] {
                let saved = GlobalScriptSettings(
                    enabled: enabled,
                    source: bundledSource,
                    updatedAt: Date(timeIntervalSince1970: 0)
                )
                let decoded = try JSONDecoder().decode(
                    GlobalScriptSettings.self,
                    from: JSONEncoder().encode(saved)
                )
                let upgraded = decoded.upgradingBundledTemplate()

                #expect(upgraded.source == GlobalScriptSettings.default.source)
                #expect(upgraded.enabled == enabled)
                #expect(upgraded.updatedAt > saved.updatedAt)
                #expect(upgraded.upgradingBundledTemplate() == upgraded)
            }
        }
    }

    @Test
    func templateUpgradePreservesCustomAndCurrentScripts() {
        for source in ["", "// My custom script", Self.originalBundledSource + "\n// Custom edit",
                       GlobalScriptSettings.default.source] {
            let saved = GlobalScriptSettings(enabled: true, source: source, updatedAt: .now)
            #expect(saved.upgradingBundledTemplate() == saved)
        }
    }

    // Exact Swift source of the template shipped before the completion fix.
    // Keep this fixture unchanged: the migration must recognize saved copies.
    private static let originalBundledSource = """
        // ==UserScript==
        // @name Cweb 全局签到
        // @match *://*/*
        // @run-at document-end
        // ==/UserScript==

        (() => {
            const api = window.CwebCheckIn;
            if (!api) return;

            const signWords = /签到|每日签到|check[\\s-]?in|daily\\s*sign/i;
            const successWords = /已签到|签到成功|已完成|success|claimed/i;
            const captchaSelectors = [
                '[class*="captcha" i]',
                '[id*="captcha" i]',
                '[class*="verify" i]',
                '[id*="verify" i]',
                'iframe[src*="captcha" i]'
            ];

            let debounceTimer;
            let noButtonTimer;
            let hasClicked = false;

            const textOf = (element) =>
                (element?.innerText || element?.textContent || "").trim();

            const findSignButton = () => [...document.querySelectorAll(
                'button, a, [role="button"]'
            )].find((element) => {
                const text = textOf(element);
                return text && signWords.test(text)
                    && !/已签到|已完成|不可用|disabled/i.test(text)
                    && !element.disabled;
            });

            const pageShowsSuccess = () => [...document.querySelectorAll(
                '[role="status"], [aria-live], .toast, .alert, button, a'
            )].some((element) => successWords.test(textOf(element)));

            const detect = () => {
                if (api.isPaused()) return;

                if (captchaSelectors.some((selector) => document.querySelector(selector))) {
                    api.captchaDetected("检测到验证码，请手动完成");
                    return;
                }

                const button = findSignButton();
                if (!button) {
                    if (!hasClicked) return;
                    if (pageShowsSuccess()) {
                        api.success("页面显示签到成功");
                    }
                    return;
                }

                clearTimeout(noButtonTimer);
                if (hasClicked) return;
                hasClicked = true;
                button.click();

                setTimeout(() => {
                    if (api.isPaused()) return;
                    if (pageShowsSuccess()) {
                        api.success("页面显示签到成功");
                    }
                }, 1200);
            };

            const schedule = () => {
                clearTimeout(debounceTimer);
                debounceTimer = setTimeout(detect, 250);
            };

            const root = document.documentElement || document;
            new MutationObserver(schedule).observe(root, {
                childList: true,
                subtree: true,
                attributes: true
            });

            window.addEventListener("cwebAutomationResume", () => {
                hasClicked = false;
                schedule();
            });

            noButtonTimer = setTimeout(() => {
                if (!hasClicked && !api.isPaused()) {
                    api.noButton("未找到签到入口");
                }
            }, 6000);

            detect();
        })();
        """

    @Test
    @MainActor
    func successfulCheckInIsLimitedToOnePerLocalDayAndProfile() throws {
        let suiteName = "ProfileBrowser.AutomationScriptTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let profileRepository = ProfileRepository(
            fileURL: directory.appending(path: "profiles.json", directoryHint: .notDirectory)
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = BrowserProfile(name: "Daily record")
        try profileRepository.save([profile])

        let model = AppModel(
            profileRepository: profileRepository,
            credentialVault: CredentialVault(inMemory: true),
            userDefaults: defaults
        )
        let profileID = profile.id
        let today = Date()
        let yesterday = try #require(Calendar.current.date(byAdding: .day, value: -1, to: today))

        #expect(model.shouldRunAutomation(for: profileID, now: today))
        model.recordAutomationSuccess(for: profileID, now: today)
        #expect(!model.shouldRunAutomation(for: profileID, now: today))
        #expect(model.shouldRunAutomation(for: profileID, now: yesterday))
        #expect(model.shouldRunAutomation(for: UUID(), now: today))
    }
    // Template shipped immediately before group check-in.
    private static let previousBundledSource = """
        // ==UserScript==
        // @name Cweb 全局签到
        // @match *://*/*
        // @run-at document-end
        // ==/UserScript==

        (() => {
            const api = window.CwebCheckIn;
            if (!api) return;

            const signWords = /签到|每日签到|check[\\s-]?in|daily\\s*sign/i;
            // A generic "success" or "已完成" elsewhere is not a check-in result.
            const completionWords = /已签到|签到成功|已完成签到|(?:今日|今天|本日)签到[：:\\s]*已完成|already\\s+(?:checked[\\s-]?in|signed[\\s-]?in)|checked[\\s-]?in\\s+today|check[\\s-]?in\\s+(?:successful|completed)|successfully\\s+checked[\\s-]?in/i;
            const captchaSelectors = [
                '[class*="captcha" i]',
                '[id*="captcha" i]',
                '[class*="verify" i]',
                '[id*="verify" i]',
                'iframe[src*="captcha" i]'
            ];

            let debounceTimer;
            let noButtonTimer;
            let successTimer;
            let hasClicked = false;
            let hasCompleted = false;

            const textOf = (element) =>
                (element?.innerText || element?.textContent || "").trim();

            const isVisible = (element) => {
                if (!element.getClientRects().length) return false;
                const visibility = window.getComputedStyle(element).visibility;
                return visibility !== "hidden" && visibility !== "collapse";
            };

            const findSignButton = () => [...document.querySelectorAll(
                'button, a, [role="button"]'
            )].find((element) => {
                const text = textOf(element);
                return isVisible(element) && text && signWords.test(text)
                    && !/已签到|已完成|不可用|disabled/i.test(text)
                    && !element.disabled
                    && element.getAttribute("aria-disabled") !== "true"
                    // SuperAPI also uses a button for its section heading.
                    // Only consider action controls when submitting a check-in.
                    && !element.querySelector("h1, h2, h3, h4, h5, h6");
            });

            const pageShowsCompletion = () => [...document.querySelectorAll(
                '[role="status"], [aria-live], .toast, .alert, button, a, [role="button"]'
            )].some((element) => {
                const text = textOf(element);
                return isVisible(element) && completionWords.test(text)
                    && !/未签到|未完成|签到失败/i.test(text);
            });

            const finish = () => {
                hasCompleted = true;
                clearTimeout(noButtonTimer);
                clearTimeout(debounceTimer);
                clearTimeout(successTimer);
                observer.disconnect();
                api.success("页面显示已完成签到");
            };

            const detect = () => {
                if (hasCompleted || api.isPaused()) return;

                if (captchaSelectors.some((selector) => [...document.querySelectorAll(selector)]
                    .some(isVisible))) {
                    api.captchaDetected("检测到验证码，请手动完成");
                    return;
                }

                if (pageShowsCompletion()) {
                    finish();
                    return;
                }

                const button = findSignButton();
                if (!button) return;

                clearTimeout(noButtonTimer);
                if (hasClicked) return;
                hasClicked = true;
                button.click();

                // Reuse the same checks so a newly displayed CAPTCHA always
                // pauses automation before any success is reported.
                successTimer = setTimeout(detect, 1200);
            };

            const schedule = () => {
                if (hasCompleted) return;
                clearTimeout(debounceTimer);
                debounceTimer = setTimeout(detect, 250);
            };

            const root = document.documentElement || document;
            const observer = new MutationObserver(schedule);
            observer.observe(root, {
                childList: true,
                subtree: true,
                attributes: true,
                characterData: true
            });

            window.addEventListener("cwebAutomationResume", () => {
                if (hasCompleted) return;
                hasClicked = false;
                schedule();
            });

            noButtonTimer = setTimeout(() => {
                if (!hasCompleted && !hasClicked && !api.isPaused()) {
                    api.noButton("未找到签到入口");
                }
            }, 6000);

            detect();
        })();
        """

}
