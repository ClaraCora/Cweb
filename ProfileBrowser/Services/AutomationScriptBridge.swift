import Foundation
import WebKit

enum AutomationBridge {
    static let messageName = "cwebAutomation"
}

enum AutomationScriptBuilder {
    static func build(code: String, matches: [String], completionKey: String? = nil) -> String {
        let matchJSON = encodeMatches(matches)
        let completionKeyJSON = encodeString(completionKey)
        return """
        (() => {
            const __cwebMatches = \(matchJSON);
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

            if (__cwebIsCompleted()) return;

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

            if (__cwebMatches.length > 0
                && !__cwebMatches.some(__cwebMatchesPage)) {
                return;
            }

            let __cwebPaused = __cwebIsPausedPersisted();
            const __cwebSent = new Set();
            const __cwebPost = (type, message = "") => {
                if (type !== "resume" && __cwebSent.has(type)) {
                    return;
                }
                if (type !== "resume") __cwebSent.add(type);
                window.webkit?.messageHandlers?.\(AutomationBridge.messageName)?.postMessage({
                    type,
                    message: String(message || "")
                });
            };

            window.CwebCheckIn = {
                isPaused: () => __cwebPaused,
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
                    __cwebPaused = true;
                    try {
                        if (__cwebPauseKey) {
                            window.localStorage.setItem(__cwebPauseKey, "1");
                        }
                    } catch (_) {}
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
                    window.dispatchEvent(new Event("cwebAutomationResume"));
                    __cwebPost("resume");
                }
            };

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
        guard let payload = message.body as? [String: Any],
              let type = payload["type"] as? String else {
            return
        }
        let messageText = payload["message"] as? String ?? ""
        let session = self.session
        Task { @MainActor in
            session?.receiveAutomationMessage(type: type, message: messageText)
        }
    }
}
