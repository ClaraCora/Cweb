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
            let submissionTimer;
            let hasClicked = false;
            let hasCompleted = false;
            let submissionFailed = false;

            const textOf = (element) =>
                (typeof element?.innerText === "string"
                    ? element.innerText : element?.textContent || "").trim();

            const isVisible = (element) => {
                if (!element.getClientRects().length) return false;
                const visibility = window.getComputedStyle(element).visibility;
                return visibility !== "hidden" && visibility !== "collapse";
            };

            const findSignButton = () => select(rule.actionSelector ||
                'button, a, [role="button"]'
            ).find((element) => {
                const text = textOf(element);
                return isVisible(element) && text && signWords.test(text)
                    && !/已签到|已完成|不可用|disabled/i.test(text)
                    && !element.disabled
                    && element.getAttribute("aria-disabled") !== "true"
                    // SuperAPI also uses a button for its section heading.
                    // Only consider action controls when submitting a check-in.
                    && !element.querySelector("h1, h2, h3, h4, h5, h6");
            });

            const historical = (text) => {
                if (/昨天|昨日|前天|历史|上次|上月|yesterday|previous|last\\s+(?:day|week|month)/i.test(text)) return true;
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
                    if (historical(textOf(current))) return true;
                    if (current.getAttribute && historical(current.getAttribute('data-date') || '')) return true;
                }
                return false;
            };

            const pageShowsCompletion = () => select(rule.completionSelector ||
                '[role="status"], [aria-live], .toast, .alert, button, a, [role="button"], p, span, div, li, td, strong'
            ).some((element) => {
                const text = textOf(element);
                return text.length <= 160 && isVisible(element) && completionWords.test(text)
                    && !hasHistoricalContext(element) && !/未签到|未完成|签到失败/i.test(text);
            });

            const pageShowsFailure = () => select(rule.failureSelector ||
                '[role="status"], [aria-live], .toast, .alert, p, span, div'
            ).some((element) => isVisible(element) && textOf(element).length <= 160
                && !hasHistoricalContext(element)
                && /签到失败|签到出错|check[\\s-]?in\\s+(?:failed|error)/i.test(textOf(element)));

            const finish = () => {
                hasCompleted = true;
                clearTimeout(noButtonTimer);
                clearTimeout(debounceTimer);
                clearTimeout(successTimer);
                clearTimeout(submissionTimer);
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

            armNoButtonTimer();

            detect();
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
            "0a086ed37b237890a33ca9c3a5cd601f866d4a1940742d14c3ba38d94709d41a",
            "6b022d4272cb410163ce49c802c932c45a9920c6e685839eed538872eb72c43c",
            "34c285f8ce439f24819a6b013f52824e3d5cefb10073403d809dd3a0a9c8a554"
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

struct AutomationEvent: Equatable, Sendable {
    let kind: AutomationEventKind
    let message: String
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
