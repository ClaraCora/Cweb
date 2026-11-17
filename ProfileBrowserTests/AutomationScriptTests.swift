import Foundation
import Testing
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
    func builderDetectsAccessibleCaptchaLabels() {
        let source = GlobalScriptSettings.default.source

        #expect(source.contains("[alt*=\"验证码\" i]"))
        #expect(source.contains("[placeholder*=\"验证码\" i]"))
        #expect(source.contains("[aria-label*=\"captcha\" i]"))
    }

    @Test
    func websiteRuleIgnoresRetiredCaptchaSettingsAndPreservesSelectors() throws {
        let data = Data(##"{"host":"example.com","balanceSelector":"#balance","captchaSelector":"#challenge","captchaAutoFillEnabled":true,"captchaAutoSubmitEnabled":true,"captchaImageSelector":"img","captchaInputSelector":"input","captchaSubmitSelector":"button","captchaExpectedLength":4}"##.utf8)
        let rule = try JSONDecoder().decode(WebsiteRule.self, from: data)
        #expect(rule.host == "example.com")
        #expect(rule.balanceSelector == "#balance")
        #expect(rule.captchaSelector == "#challenge")
        let encoded = try JSONEncoder().encode(rule)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object.keys.filter { $0.hasPrefix("captcha") } == ["captchaSelector"])
        #expect(try JSONDecoder().decode(WebsiteRule.self, from: encoded) == rule)
    }

    @Test
    func websiteRuleMatchesLoginAndRedirectSubdomains() {
        let rule = WebsiteRule(host: "cf.sheapi.cc")
        #expect(rule.matches(host: "cf.sheapi.cc"))
        #expect(rule.matches(host: "www.sheapi.cc"))
        #expect(rule.matches(host: "sheapi.cc"))
        #expect(!rule.matches(host: "example.cc"))
    }

    @Test(arguments: ["cf.example.invalid", "www.example.invalid"])
    @MainActor
    func captchaWaitsForManualInputWithoutFillingOrSubmitting(host: String) async throws {
        let session = BrowserSession(profile: BrowserProfile(name: "手动验证码", homePage: URL(string: "https://cf.example.invalid/profile")!))
        defer { session.close() }
        session.configureAutomation(settings: GlobalScriptSettings(enabled: true,
            source: GlobalScriptSettings.default.source, updatedAt: .now,
            siteRules: [WebsiteRule(host: "cf.example.invalid")]), shouldRunToday: true,
            completionKey: UUID().uuidString)
        let html = """
        <html><body><div class="captcha"><input placeholder="请输入验证码"><button>确认</button></div>
        <script>window.submits = 0; document.querySelector('button').onclick = () => window.submits++;</script>
        </body></html>
        """
        for try await _ in session.page.load(html: html, baseURL: URL(string: "https://\(host)/profile")!) { }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while session.automationState != .captcha && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(session.automationState == .captcha)
        await session.recheckAutomation()
        session.receiveAutomationMessage(type: "error", message: "late timeout")
        session.receiveAutomationMessage(type: "resume", message: "late resume")
        #expect(session.automationState == .captcha)
        let state = try #require(try await session.page.callJavaScript("""
        return { value: document.querySelector('input').value, submits: window.submits,
            paused: window.CwebCheckIn.isPaused(), fillType: typeof window.CwebCheckIn.fillCaptcha,
            captureType: typeof window.CwebCheckIn.captureCaptcha };
        """) as? [String: Any])
        #expect(state["value"] as? String == "")
        #expect(state["submits"] as? Int == 0)
        #expect(state["paused"] as? Bool == true)
        #expect(state["fillType"] as? String == "undefined")
        #expect(state["captureType"] as? String == "undefined")
        _ = try await session.page.callJavaScript("""
        document.querySelector('input').value = '2746';
        document.querySelector('.captcha').remove();
        const status = document.createElement('p'); status.textContent = '今天已完成签到';
        document.body.append(status);
        """)
        await session.recheckAutomation()
        #expect(session.automationState == .captcha)
        await session.resumeAutomation()
        let resumedDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        while session.automationState != .success && ContinuousClock.now < resumedDeadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(session.automationState == .success)
        #expect(try await session.page.callJavaScript("return window.submits;") as? Int == 0)
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
    func originalBundledTemplateUpgradesWithoutChangingEnabledState() throws {
        for enabled in [false, true] {
            for bundledSource in [Self.originalBundledSource, Self.previousBundledSource, Self.retiredOCRBundledSource] {
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

    private static let retiredOCRBundledSource = """
        // ==UserScript==
        // @name Cweb 全局签到
        // @match *://*/*
        // @run-at document-end
        // ==/UserScript==

        (() => {
            const api = window.CwebCheckIn;
            if (!api) return;
            const rule = window.CwebSiteRule || {};
            const select = (selector) => {
                try {
                    const root = rule.checkInContainerSelector
                        ? document.querySelectorAll(rule.checkInContainerSelector)[0] : document;
                    return root ? [...root.querySelectorAll(selector)] : [];
                } catch (_) { return []; }
            };

            const signWords = /^(?:立即签到|每日签到|签到|去签到|check[\\s-]?in|daily\\s*sign(?:[\\s-]?in)?)$/i;
            // A generic "success" or "已完成" elsewhere is not a check-in result.
            const completionWords = /已签到|签到成功|已完成签到|(?:今日|今天|本日)签到[：:\\s]*已完成|already\\s+(?:checked[\\s-]?in|signed[\\s-]?in)|checked[\\s-]?in\\s+today|check[\\s-]?in\\s+(?:successful|completed)|successfully\\s+checked[\\s-]?in/i;
            const captchaSelectors = [
                '[class*="captcha" i]',
                '[id*="captcha" i]',
                '[aria-label*="captcha" i]',
                '[aria-label*="验证码" i]',
                '[alt*="captcha" i]',
                '[alt*="验证码" i]',
                '[placeholder*="captcha" i]',
                '[placeholder*="验证码" i]',
                'iframe[src*="captcha" i]',
                'iframe[src*="challenges.cloudflare.com" i]',
                '.g-recaptcha', '.h-captcha', '.cf-turnstile'
            ];

            let debounceTimer;
            let noButtonTimer;
            let successTimer;
            let submissionTimer;
            let hasClicked = false;
            let hasCompleted = false;
            let submissionFailed = false;
            var captchaCaptureInFlight = false;
            let captchaCaptureGeneration = 0;

            const textOf = (element) =>
                (typeof element?.innerText === "string"
                    ? element.innerText : element?.textContent || "").trim();

            const isVisible = (element) => {
                if (!element.getClientRects().length) return false;
                const visibility = window.getComputedStyle(element).visibility;
                return visibility !== "hidden" && visibility !== "collapse";
            };

            const queryVisible = (root, selector) => {
                try {
                    return [...(root?.querySelectorAll?.(selector) || [])].find(isVisible) || null;
                } catch (_) {
                    return null;
                }
            };

            const captchaRoot = () => {
                if (rule.captchaSelector) {
                    try {
                        return [...document.querySelectorAll(rule.captchaSelector)].find(isVisible) || null;
                    } catch (_) {
                        return null;
                    }
                }
                return captchaSelectors.map((selector) => queryVisible(document, selector)).find(Boolean) || null;
            };

            const captchaInput = (root) => {
                const selector = rule.captchaInputSelector ||
                    'input:not([type="hidden"]):not([type="password"]):not([type="checkbox"]):not([type="radio"])';
                const candidates = [];
                if (root?.matches?.(selector)) candidates.push(root);
                candidates.push(...(root?.querySelectorAll?.(selector) || []));
                if (root !== document) candidates.push(...(document.querySelectorAll(selector) || []));
                return candidates.find((element) => {
                    if (!isVisible(element)) return false;
                    if (rule.captchaInputSelector) return true;
                    const metadata = [element.name, element.id, element.placeholder,
                        element.autocomplete, element.getAttribute('aria-label')].filter(Boolean).join(' ');
                    return /captcha|verify|verification|验证码|校验|code/i.test(metadata)
                        || (element.maxLength >= 4 && element.maxLength <= 8);
                }) || null;
            };

            const captchaImage = (root) => {
                const selector = rule.captchaImageSelector || 'img, canvas';
                const candidates = [];
                if (root?.matches?.(selector)) candidates.push(root);
                candidates.push(...(root?.querySelectorAll?.(selector) || []));
                if (root !== document) candidates.push(...(document.querySelectorAll(selector) || []));
                return candidates.find((element) => {
                    if (!isVisible(element)) return false;
                    if (rule.captchaImageSelector) return true;
                    const metadata = [element.id, element.className, element.alt,
                        element.getAttribute('aria-label')].filter((value) => typeof value === 'string').join(' ');
                    return element.tagName === 'CANVAS'
                        || /captcha|verify|验证码|校验/i.test(metadata)
                        || (element.tagName === 'IMG' && element.naturalWidth > 0);
                }) || null;
            };

            const extractCaptchaImage = async (element) => {
                if (!element) return null;
                if (element.tagName === 'CANVAS') {
                    try { return element.toDataURL('image/png'); } catch (_) { return null; }
                }
                if (element.tagName !== 'IMG') return null;
                if (!element.complete || !element.naturalWidth) {
                    const loaded = await new Promise((resolve) => {
                        let settled = false;
                        const finish = (value) => {
                            if (settled) return;
                            settled = true;
                            clearTimeout(timer);
                            element.removeEventListener('load', onLoad);
                            element.removeEventListener('error', onError);
                            resolve(value);
                        };
                        const onLoad = () => finish(Boolean(element.naturalWidth));
                        const onError = () => finish(false);
                        const timer = setTimeout(() => finish(false), 1500);
                        element.addEventListener('load', onLoad, { once: true });
                        element.addEventListener('error', onError, { once: true });
                        if (element.complete && element.naturalWidth) finish(true);
                    });
                    if (!loaded || !element.naturalWidth) return null;
                }
                if (element.currentSrc?.startsWith('data:')) return element.currentSrc;
                try {
                    const canvas = document.createElement('canvas');
                    canvas.width = element.naturalWidth;
                    canvas.height = element.naturalHeight;
                    const context = canvas.getContext('2d');
                    if (!context) return null;
                    context.drawImage(element, 0, 0);
                    return canvas.toDataURL('image/png');
                } catch (_) {
                    return null;
                }
            };

            const prepareCaptcha = async () => {
                if (!rule.captchaAutoFillEnabled) return null;
                const root = captchaRoot();
                const input = captchaInput(root);
                const image = captchaImage(root);
                if (!input || !image) return null;
                input.scrollIntoView({ block: 'center', behavior: 'smooth' });
                input.focus({ preventScroll: true });
                const imageData = await extractCaptchaImage(image);
                if (!imageData) return null;
                __cwebCaptchaInput = input;
                __cwebCaptchaSubmit = rule.captchaSubmitSelector
                    ? (queryVisible(root || document, rule.captchaSubmitSelector)
                        || queryVisible(document, rule.captchaSubmitSelector))
                    : null;
                return {
                    mode: 'imageDigits',
                    imageData,
                    expectedLength: Number.isInteger(rule.captchaExpectedLength)
                        ? rule.captchaExpectedLength : null
                };
            };

            const findSignButton = () => select(rule.actionSelector ||
                'button, a, [role="button"]'
            ).find((element) => {
                const text = textOf(element);
                return isVisible(element) && text && (rule.actionSelector || signWords.test(text))
                    && (rule.actionSelector || !/记录|规则|说明|历史|history|record|rules/i.test(text))
                    && !/已签到|已完成|不可用|disabled/i.test(text)
                    && !element.disabled
                    && element.getAttribute("aria-disabled") !== "true"
                    // SuperAPI also uses a button for its section heading.
                    // Only consider action controls when submitting a check-in.
                    && !element.querySelector("h1, h2, h3, h4, h5, h6");
            });

            const historical = (text) => {
                if (/昨天|昨日|前天|历史|上次|上月|累计|累計|统计|統計|天数|天數|本月|本周|连续|連續|记录|記錄|total|streak|history|statistics|yesterday|previous|last\\s+(?:day|week|month)/i.test(text)) return true;
                const date = text.match(/(20\\d{2})[-/.年](\\d{1,2})[-/.月](\\d{1,2})/);
                if (!date) return false;
                const today = new Date();
                return Number(date[1]) !== today.getFullYear()
                    || Number(date[2]) !== today.getMonth() + 1 || Number(date[3]) !== today.getDate();
            };

            const hasHistoricalContext = (element) => {
                let current = element;
                for (let depth = 0; current && depth < 4; depth++, current = current.parentElement) {
                    if (current === document.body || current === document.documentElement) break;
                    const text = textOf(current);
                    // History rows carry their own date/status. A surrounding
                    // dashboard may also contain unrelated statistics or links.
                    const tag = String(current.tagName || current.tag || '').toLowerCase();
                    const context = current.getAttribute?.('class') || '';
                    const historicalRow = /^(li|tr)$/.test(tag) || /history|record|statistic|streak|checkin-log/i.test(context);
                    if ((current === element || historicalRow) && historical(text)) return true;
                    if (current !== element && /(?:累计|累計|连续|連續|本月|本周|total|streak)[^\\n。]{0,12}(?:已签到|签到成功)|(?:已签到|签到成功)[：:\\s]*\\d+\\s*(?:天|次|days)/i.test(text)) return true;
                    if (current.getAttribute && historical(current.getAttribute('data-date') || '')) return true;
                }
                return false;
            };

            const pageShowsCompletion = () => select(rule.completionSelector ||
                '[role="status"], [aria-live], .toast, .alert, button, a, [role="button"], p, span, div, li, td, strong'
            ).some((element) => {
                const text = textOf(element);
                return text.length <= 160 && isVisible(element) && (rule.completionSelector || completionWords.test(text))
                    && !hasHistoricalContext(element) && !/未签到|未完成|签到失败/i.test(text);
            });

            const pageShowsFailure = () => select(rule.failureSelector ||
                '[role="status"], [aria-live], .toast, .alert, p, span, div'
            ).some((element) => isVisible(element) && textOf(element).length <= 160
                && !hasHistoricalContext(element)
                && (rule.failureSelector || /签到失败|签到出错|check[\\s-]?in\\s+(?:failed|error)/i.test(textOf(element))));

            const finish = () => {
                hasCompleted = true;
                stopDetection();
                api.success("页面显示已完成签到");
            };

            const stopDetection = () => {
                captchaCaptureGeneration++;
                captchaCaptureInFlight = false;
                clearTimeout(noButtonTimer);
                clearTimeout(debounceTimer);
                clearTimeout(successTimer);
                clearTimeout(submissionTimer);
                observer.disconnect();
            };

            // This is also the explicit retry entry point. Capture the current
            // DOM image; never reuse the previous challenge's image bytes.
            api.captureCaptcha = async () => {
                if (hasCompleted || captchaCaptureInFlight) return;
                api.pause();
                if (api.hasFilledCaptcha?.()) {
                    api.captchaDetected("验证码已填入，请完成验证后继续检测");
                    return;
                }
                const generation = ++captchaCaptureGeneration;
                captchaCaptureInFlight = true;
                try {
                    const challenge = await prepareCaptcha();
                    if (hasCompleted || generation !== captchaCaptureGeneration || !api.isPaused()) return;
                    api.captchaDetected(challenge
                        ? "检测到数字图片验证码，正在识别。"
                        : "无法读取验证码图片，请手动输入。", challenge);
                } catch (_) {
                    if (generation === captchaCaptureGeneration && api.isPaused()) {
                        api.captchaDetected("无法读取验证码图片，请手动输入。");
                    }
                } finally {
                    if (generation === captchaCaptureGeneration) captchaCaptureInFlight = false;
                }
            };

            const detect = async () => {
                if (hasCompleted || api.isPaused()) return;
                try {
                    for (const key of ['checkInContainerSelector', 'actionSelector', 'completionSelector', 'failureSelector',
                        'captchaSelector', 'captchaImageSelector', 'captchaInputSelector', 'captchaSubmitSelector']) {
                        if (rule[key]) document.querySelectorAll(rule[key]);
                    }
                } catch (_) {
                    clearTimeout(noButtonTimer);
                    api.error("网站选择器无效，请检查网站规则");
                    return;
                }

                if ((rule.captchaSelector ? [rule.captchaSelector] : captchaSelectors).some((selector) => {
                    try { return [...document.querySelectorAll(selector)].some(isVisible); }
                    catch (_) { api.error("验证码选择器无效，请检查网站规则"); return false; }
                })) {
                    if (captchaCaptureInFlight) return;
                    if (rule.captchaAutoFillEnabled) {
                        await api.captureCaptcha();
                        return;
                    }
                    api.captchaDetected("检测到验证码，请手动完成");
                    return;
                }

                if (pageShowsCompletion()) {
                    finish();
                    return;
                }

                if (hasClicked && pageShowsFailure()) {
                    clearTimeout(submissionTimer);
                    submissionFailed = true;
                    api.error("签到提交失败，请检查页面后手动重试或跳过");
                    return;
                }

                const button = findSignButton();
                if (!button) return;

                clearTimeout(noButtonTimer);
                if (hasClicked) return;
                hasClicked = true;
                submissionTimer = setTimeout(() => {
                    if (!hasCompleted && !api.isPaused()) {
                        submissionFailed = true;
                        api.error("提交后未收到签到结果，请检查页面后手动重试或跳过");
                    }
                }, Math.max(5, Math.min(120, rule.submissionTimeoutSeconds || 30)) * 1000);
                button.click();

                // Reuse the same checks so a newly displayed CAPTCHA always
                // pauses automation before any success is reported.
                successTimer = setTimeout(() => { void detect(); }, 1200);
            };

            const schedule = () => {
                if (hasCompleted || api.isPaused()) return;
                clearTimeout(debounceTimer);
                debounceTimer = setTimeout(() => { void detect(); }, 250);
            };

            const root = document.documentElement || document;
            const observer = new MutationObserver(schedule);
            const observe = () => observer.observe(root, {
                childList: true,
                subtree: true,
                attributes: true,
                characterData: true
            });

            window.addEventListener("cwebAutomationPause", stopDetection);

            window.addEventListener("cwebAutomationResume", () => {
                if (hasCompleted) return;
                captchaCaptureGeneration++;
                captchaCaptureInFlight = false;
                observe();
                if (submissionFailed) { hasClicked = false; submissionFailed = false; }
                clearTimeout(submissionTimer);
                if (hasClicked) {
                    submissionTimer = setTimeout(() => {
                        if (!hasCompleted && !api.isPaused()) {
                            submissionFailed = true;
                            api.error("提交后未收到签到结果，请检查页面后手动重试或跳过");
                        }
                    }, Math.max(5, Math.min(120, rule.submissionTimeoutSeconds || 30)) * 1000);
                }
                armNoButtonTimer();
                schedule();
            });

            window.addEventListener("cwebAutomationRecheck", schedule);

            const armNoButtonTimer = () => {
                clearTimeout(noButtonTimer);
                noButtonTimer = setTimeout(() => {
                    if (!hasCompleted && !hasClicked && !api.isPaused()) {
                        api.noButton("未找到签到入口");
                    }
                }, 6000);
            };

            if (!api.isPaused()) {
                observe();
                armNoButtonTimer();
            }

            void detect();
        })();
        """

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
