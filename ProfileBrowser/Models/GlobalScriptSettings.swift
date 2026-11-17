import CryptoKit
import Foundation

struct GlobalScriptSettings: Codable, Equatable, Sendable {
    var enabled: Bool
    var source: String
    var updatedAt: Date
    var siteRules: [WebsiteRule]? = nil

    static let `default` = GlobalScriptSettings(
        enabled: false,
        source: """
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
        """,
        updatedAt: .now
    )

    /// Upgrade only an unmodified copy of the original bundled template.
    /// Saved custom scripts, including blank scripts, remain untouched.
    func upgradingBundledTemplate() -> GlobalScriptSettings {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = SHA256.hash(data: Data(normalized.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let bundledFingerprints: Set<String> = [
            "0471f26f7d022c72130828a52976c180468d2711d041c60c8473dbf83ab7ebd5",
            "0a086ed37b237890a33ca9c3a5cd601f866d4a1940742d14c3ba38d94709d41a",
            "6b022d4272cb410163ce49c802c932c45a9920c6e685839eed538872eb72c43c",
            "34c285f8ce439f24819a6b013f52824e3d5cefb10073403d809dd3a0a9c8a554",
            "7e3e09a0361a8fa7148b861b0bbe7ac44d2f2d6058b6216f2d86f99965abb6b6"
        ]
        guard bundledFingerprints.contains(digest) else {
            return self
        }
        var upgraded = self
        upgraded.source = Self.default.source
        upgraded.updatedAt = .now
        return upgraded
    }
}

enum AutomationEventKind: String, Codable, Sendable {
    case success
    case captcha
    case noButton
    case error
    case resume
}

enum CaptchaChallengeMode: String, Sendable {
    case imageDigits
}

struct CaptchaChallenge: Equatable, Sendable {
    let mode: CaptchaChallengeMode
    let documentID: String
    let imageData: Data?
    let expectedLength: Int?
}

struct AutomationEvent: Equatable, Sendable {
    let kind: AutomationEventKind
    let message: String
    let captcha: CaptchaChallenge?

    init(kind: AutomationEventKind, message: String, captcha: CaptchaChallenge? = nil) {
        self.kind = kind
        self.message = message
        self.captcha = captcha
    }
}

struct AutomationRunRecord: Codable, Equatable, Sendable {
    let profileID: UUID
    let kind: AutomationEventKind
    let message: String
    let date: Date
}

enum AutomationState: Equatable, Sendable {
    case inactive
    case running
    case skipped
    case success
    case captcha
    case noButton
    case error
}

struct ParsedAutomationScript: Sendable {
    let source: String
    let matches: [String]
    let runsAtDocumentStart: Bool
}

enum AutomationScriptParser {
    static func parse(_ source: String) -> ParsedAutomationScript {
        var codeLines: [String] = []
        var matches: [String] = []
        var runsAtDocumentStart = false
        var inMetadata = false

        for line in source.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "// ==UserScript==" {
                inMetadata = true
                continue
            }
            if inMetadata, trimmed == "// ==/UserScript==" {
                inMetadata = false
                continue
            }

            guard inMetadata else {
                codeLines.append(line)
                continue
            }

            let metadata = trimmed.dropFirst(2)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if metadata.hasPrefix("@match") {
                let pattern = String(metadata.dropFirst("@match".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !pattern.isEmpty {
                    matches.append(pattern)
                }
            } else if metadata.hasPrefix("@run-at") {
                let value = String(metadata.dropFirst("@run-at".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                runsAtDocumentStart = value == "document-start"
            }
        }

        return ParsedAutomationScript(
            source: codeLines.joined(separator: "\n"),
            matches: matches,
            runsAtDocumentStart: runsAtDocumentStart
        )
    }
}
