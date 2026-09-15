import CryptoKit
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
        guard digest == "0a086ed37b237890a33ca9c3a5cd601f866d4a1940742d14c3ba38d94709d41a" else {
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
