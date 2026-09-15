import Foundation

struct GlobalScriptSettings: Codable, Equatable, Sendable {
    var enabled: Bool
    var source: String
    var updatedAt: Date

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
        """,
        updatedAt: .now
    )
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
