import Foundation
import CoreGraphics
import CoreText
import ImageIO
import Testing
import UniformTypeIdentifiers
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
        #expect(source.contains("details = null"))
        #expect(source.contains("payload.captcha"))
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
        #expect(rule.captchaImageSelector == nil)
        #expect(rule.captchaInputSelector == nil)
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

    private static func syntheticCaptchaImage() -> Data? {
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
            NSAttributedString(string: "2746", attributes: attributes)
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
