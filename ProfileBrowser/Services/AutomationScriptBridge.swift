import Foundation
import WebKit

enum AutomationBridge {
    static let messageName = "cwebAutomation"
}

enum AutomationScriptBuilder {
    static func build(code: String, matches: [String], completionKey: String? = nil, siteRules: [WebsiteRule] = [], runToken: String? = nil, homeOrigin: String? = nil) -> String {
        let runTokenJSON = encodeString(runToken)
        let homeOriginJSON = encodeString(homeOrigin)
        let matchJSON = encodeMatches(matches)
        let completionKeyJSON = encodeString(completionKey)
        let rulesJSON = String(data: (try? JSONEncoder().encode(siteRules)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
        return """
        (() => {
            const __cwebMatches = \(matchJSON);
            const __cwebRules = \(rulesJSON);
            const __cwebNormalizeHost = (value) => String(value || '')
                .trim().toLowerCase().replace(/\\.+$/, '');
            const __cwebSiteHost = (value) => {
                const host = __cwebNormalizeHost(value);
                const labels = host.split('.').filter(Boolean);
                if (labels.length < 2 || labels.every((label) => /^\\d+$/.test(label))) return host;
                const suffix = labels.slice(-2).join('.');
                const commonTwoLabelSuffixes = new Set([
                    'co.uk', 'org.uk', 'ac.uk', 'gov.uk', 'com.au', 'net.au',
                    'org.au', 'co.jp', 'com.cn', 'net.cn', 'org.cn'
                ]);
                const count = commonTwoLabelSuffixes.has(suffix) ? 3 : 2;
                return labels.slice(-count).join('.');
            };
            const __cwebMatchesHost = (left, right) => {
                const a = __cwebNormalizeHost(left);
                const b = __cwebNormalizeHost(right);
                return Boolean(a && b) && (a === b || __cwebSiteHost(a) === __cwebSiteHost(b));
            };
            const __cwebPageHost = __cwebNormalizeHost(window.location.hostname);
            window.CwebSiteRule = __cwebRules.find(rule =>
                __cwebMatchesHost(rule.host, __cwebPageHost)) || {};
            const __cwebCompletionKey = \(completionKeyJSON);
            const __cwebPauseKey = __cwebCompletionKey
                ? __cwebCompletionKey + ".paused"
                : null;
            const __cwebIsCompleted = () => {
                if (!__cwebCompletionKey) return false;
                try {
                    return window.localStorage.getItem(__cwebCompletionKey) === "1";
                } catch (_) {
                    return false;
                }
            };

            const __cwebIsPausedPersisted = () => {
                if (!__cwebPauseKey) return false;
                try {
                    return window.localStorage.getItem(__cwebPauseKey) === "1";
                } catch (_) {
                    return false;
                }
            };

            const __cwebMatchesPage = (pattern) => {
                if (pattern === "<all_urls>") return true;
                try {
                    const escaped = pattern
                        .split("*")
                        .map((part) => part.replace(/[\\^$+?.()|[\\]{}]/g, "\\\\$&"))
                        .join(".*");
                    return new RegExp("^" + escaped + "$", "i").test(window.location.href);
                } catch (_) {
                    return false;
                }
            };

            const __cwebHomeOrigin = \(homeOriginJSON);
            const __cwebHomeHost = (() => {
                try { return __cwebNormalizeHost(new URL(__cwebHomeOrigin || window.location.origin).hostname); }
                catch (_) { return ''; }
            })();
            const __cwebExplicitMatches = __cwebMatches.filter(p => p !== '*://*/*' && p !== '<all_urls>');
            const __cwebAllowed = __cwebExplicitMatches.length > 0
                ? __cwebExplicitMatches.some(__cwebMatchesPage)
                : !__cwebHomeOrigin || window.location.origin === __cwebHomeOrigin
                    || __cwebMatchesHost(__cwebHomeHost, __cwebPageHost)
                    || __cwebRules.some(r => __cwebMatchesHost(r.host, __cwebPageHost));
            if (!__cwebAllowed || (__cwebMatches.length > 0
                && !__cwebMatches.some(__cwebMatchesPage))) {
                return;
            }

            let __cwebPaused = Boolean(window.__cwebAutomationManuallyPaused) || __cwebIsPausedPersisted();
            const __cwebSent = new Set();
            const __cwebPost = (type, message = "") => {
                if (type !== "resume" && __cwebSent.has(type)) {
                    return;
                }
                if (type !== "resume") __cwebSent.add(type);
                const payload = {
                    type, runToken: \(runTokenJSON), documentID: window.__cwebDocumentID,
                    message: String(message || "")
                };
                window.webkit?.messageHandlers?.\(AutomationBridge.messageName)?.postMessage(payload);
            };

            window.CwebCheckIn = {
                isPaused: () => __cwebPaused,
                pause: () => {
                    __cwebPaused = true;
                    try {
                        if (__cwebPauseKey) window.localStorage.setItem(__cwebPauseKey, "1");
                    } catch (_) {}
                    window.dispatchEvent(new Event("cwebAutomationPause"));
                },
                success: (message) => {
                    if (!__cwebPaused) {
                        try {
                            if (__cwebCompletionKey) {
                                window.localStorage.setItem(__cwebCompletionKey, "1");
                            }
                        } catch (_) {}
                        __cwebPost("success", message);
                    }
                },
                captchaDetected: (message) => {
                    window.CwebCheckIn.pause();
                    __cwebPost("captcha", message);
                },
                noButton: (message) => __cwebPost("noButton", message),
                error: (message) => __cwebPost("error", message),
                resume: () => {
                    __cwebPaused = false;
                    try {
                        if (__cwebPauseKey) {
                            window.localStorage.removeItem(__cwebPauseKey);
                        }
                    } catch (_) {}
                    __cwebSent.clear();
                    __cwebPost("resume");
                    if (__cwebIsCompleted()) {
                        __cwebPost("success", "今天已完成签到");
                    } else {
                        window.dispatchEvent(new Event("cwebAutomationResume"));
                    }
                }
            };

            // Keep the API available while manually paused so resuming can
            // deliver a completion that native code deferred during the pause.
            if (__cwebIsCompleted()) {
                if (!window.__cwebAutomationManuallyPaused) {
                    __cwebPost("success", "今天已完成签到");
                }
                return;
            }

            if (__cwebPaused) __cwebPost("captcha", "检测已暂停，可处理验证码后继续检测");

            try {
                \(code)
            } catch (error) {
                window.CwebCheckIn.error(error?.message || String(error));
            }
        })();
        """
    }

    private static func encodeMatches(_ matches: [String]) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: matches,
            options: [.withoutEscapingSlashes]
        ),
              let value = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return value
    }

    private static func encodeString(_ value: String?) -> String {
        guard let value,
              let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8) else {
            return "null"
        }
        return encoded
    }
}

final class AutomationMessageHandler: NSObject, WKScriptMessageHandler {
    weak var session: BrowserSession?

    init(session: BrowserSession) {
        self.session = session
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              let payload = message.body as? [String: Any],
              let type = payload["type"] as? String else {
            return
        }
        guard let runToken = payload["runToken"] as? String,
              let documentID = payload["documentID"] as? String else { return }
        let messageText = payload["message"] as? String ?? ""
        let frameURL = message.frameInfo.request.url
        let session = self.session
        Task { @MainActor in
            await session?.receiveDocumentMessage(type: type, message: messageText,
                runToken: runToken, documentID: documentID, frameURL: frameURL)
        }
    }

}
