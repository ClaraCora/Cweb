import CoreGraphics
import Foundation
import ImageIO
import Vision
import WebKit

enum AutomationBridge {
    static let messageName = "cwebAutomation"
}

enum AutomationScriptBuilder {
    // WebPage.callJavaScript exposes named arguments directly and requires an
    // explicit return statement to send the fill result back to Swift.
    static let captchaFillCall = """
    if (typeof documentID !== 'undefined' && window.__cwebDocumentID !== documentID) return false;
    return window.CwebCheckIn?.fillCaptcha?.(code) === true;
    """

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
            let __cwebCaptchaInput = null;
            let __cwebCaptchaSubmit = null;
            let __cwebCaptchaFilled = false;
            let __cwebCaptchaSubmitted = false;
            const __cwebIsVisible = (element) => {
                if (!element || !element.getClientRects?.().length) return false;
                const visibility = window.getComputedStyle(element).visibility;
                return visibility !== "hidden" && visibility !== "collapse";
            };
            const __cwebResolveCaptchaInput = () => {
                const selector = window.CwebSiteRule?.captchaInputSelector;
                if (selector) {
                    try {
                        const candidates = [...document.querySelectorAll(selector)];
                        __cwebCaptchaInput = candidates.find(__cwebIsVisible) || null;
                    } catch (_) {
                        return null;
                    }
                }
                return __cwebCaptchaInput?.isConnected && __cwebIsVisible(__cwebCaptchaInput)
                    && __cwebCaptchaInput instanceof HTMLInputElement
                    && !__cwebCaptchaInput.disabled && !__cwebCaptchaInput.readOnly
                    ? __cwebCaptchaInput : null;
            };
            const __cwebPost = (type, message = "", details = null) => {
                if (type !== "resume" && __cwebSent.has(type)) {
                    return;
                }
                if (type !== "resume") __cwebSent.add(type);
                const payload = {
                    type, runToken: \(runTokenJSON), documentID: window.__cwebDocumentID,
                    message: String(message || "")
                };
                if (details && typeof details === "object") payload.captcha = details;
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
                captchaDetected: (message, details = null) => {
                    window.CwebCheckIn.pause();
                    __cwebPost("captcha", message, details);
                },
                hasFilledCaptcha: () => __cwebCaptchaFilled,
                hasSubmittedCaptcha: () => __cwebCaptchaSubmitted,
                retryCaptcha: () => {
                    if (!__cwebPaused || typeof window.CwebCheckIn.captureCaptcha !== "function") return false;
                    __cwebCaptchaFilled = false;
                    __cwebCaptchaSubmitted = false;
                    __cwebCaptchaInput = null;
                    __cwebCaptchaSubmit = null;
                    __cwebSent.delete("captcha");
                    void window.CwebCheckIn.captureCaptcha();
                    return true;
                },
                fillCaptcha: (code) => {
                    if (__cwebCaptchaFilled) return false;
                    const value = String(code || "").replace(/[^0-9]/g, "");
                    const input = __cwebResolveCaptchaInput();
                    if (!value || !input) return false;
                    // Set the latch before events: a page may synchronously
                    // replace its form or dispatch automation callbacks.
                    __cwebCaptchaFilled = true;
                    input.focus({ preventScroll: true });
                    const descriptor = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value");
                    if (descriptor?.set) descriptor.set.call(input, value);
                    else input.value = value;
                    input.dispatchEvent(new Event("input", { bubbles: true, composed: true }));
                    input.dispatchEvent(new Event("change", { bubbles: true, composed: true }));
                    if (input.value !== value) {
                        __cwebCaptchaFilled = false;
                        return false;
                    }
                    window.CwebCheckIn.pause();
                    if (window.CwebSiteRule?.captchaAutoSubmitEnabled === true
                        && window.CwebSiteRule?.captchaSubmitSelector) {
                        try {
                            __cwebCaptchaSubmit = [...document.querySelectorAll(window.CwebSiteRule.captchaSubmitSelector)]
                                .find(element => __cwebIsVisible(element) && !element.disabled
                                    && element.getAttribute('aria-disabled') !== 'true') || null;
                        } catch (_) { __cwebCaptchaSubmit = null; }
                        if (__cwebCaptchaSubmit?.isConnected) {
                            __cwebCaptchaSubmitted = true;
                            __cwebCaptchaSubmit.click();
                        }
                    }
                    return true;
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
        let captcha = Self.captchaChallenge(from: payload, documentID: documentID)
        let frameURL = message.frameInfo.request.url
        let session = self.session
        Task { @MainActor in
            await session?.receiveDocumentMessage(type: type, message: messageText,
                runToken: runToken, documentID: documentID, frameURL: frameURL, captcha: captcha)
        }
    }

    private static func captchaChallenge(from payload: [String: Any], documentID: String) -> CaptchaChallenge? {
        guard let details = payload["captcha"] as? [String: Any],
              let mode = details["mode"] as? String,
              let challengeMode = CaptchaChallengeMode(rawValue: mode) else {
            return nil
        }
        let imageData: Data?
        if let encoded = details["imageData"] as? String {
            let value = encoded.split(separator: ",", maxSplits: 1).last.map(String.init) ?? encoded
            imageData = Data(base64Encoded: value)
        } else {
            imageData = nil
        }
        let expectedLength = (details["expectedLength"] as? NSNumber)?.intValue
        return CaptchaChallenge(
            mode: challengeMode,
            documentID: documentID,
            imageData: imageData,
            expectedLength: expectedLength
        )
    }
}

enum CaptchaOCRResult: Equatable, Sendable {
    case recognized(code: String, confidence: Double)
    case unavailable(String)
}

enum CaptchaRecognitionState: Equatable, Sendable {
    case idle
    case recognizing
    case filled
    case submitted
    case needsManual

    var message: String? {
        switch self {
        case .idle: nil
        case .recognizing: "正在识别验证码…"
        case .filled: "验证码已填入，检测已暂停。完成验证后点击“继续检测”。"
        case .submitted: "验证码已填入并提交一次，检测已暂停。点击“继续检测”查看结果。"
        case .needsManual: "无法可靠识别，请手动输入验证码。"
        }
    }
}

/// On-device OCR for simple, numeric image challenges. The service deliberately
/// rejects anything outside a conservative digit-only result so an uncertain
/// recognition never submits a wrong code.
actor CaptchaOCRService {
    private let context = CIContext(options: nil)

    func recognize(imageData: Data, expectedLength: Int?) -> CaptchaOCRResult {
        guard let images = makeImages(from: imageData), !images.isEmpty else {
            return .unavailable("无法读取验证码图片")
        }

        var best: (code: String, confidence: Double)?
        for image in images {
            guard let candidate = recognize(image: image, expectedLength: expectedLength) else { continue }
            if best == nil || candidate.confidence > best!.confidence {
                best = candidate
            }
        }
        guard let best else { return .unavailable("无法可靠识别") }
        return .recognized(code: best.code, confidence: best.confidence)
    }

    private func recognize(image: CGImage, expectedLength: Int?) -> (code: String, confidence: Double)? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.customWords = (0...9).map(String.init)
        request.usesLanguageCorrection = false
        // SheApi and similar compact captchas can place the outer digits at
        // only a few pixels of normalized height. Filtering below 0.01 drops
        // those characters even when Vision has a high-confidence result.
        request.minimumTextHeight = 0.001

        do {
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])
        } catch {
            return nil
        }

        let observations = (request.results ?? []).sorted {
            if abs($0.boundingBox.minY - $1.boundingBox.minY) > 0.05 {
                return $0.boundingBox.minY > $1.boundingBox.minY
            }
            return $0.boundingBox.minX < $1.boundingBox.minX
        }
        guard !observations.isEmpty else { return nil }

        var confidenceTotal = 0.0
        var confidenceCount = 0
        var rawText = ""
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            rawText += candidate.string
            confidenceTotal += Double(candidate.confidence)
            confidenceCount += 1
        }
        guard rawText.allSatisfy({ $0.isWhitespace || $0.isNumber }) else { return nil }

        let code = rawText.compactMap(Self.asASCIIDigit).map(String.init).joined()
        let validLength = expectedLength.map { code.count == $0 } ?? (4...8).contains(code.count)
        guard validLength else { return nil }

        let confidence = confidenceCount == 0 ? 0 : confidenceTotal / Double(confidenceCount)
        guard confidence >= 0.80 else { return nil }
        return (code, confidence)
    }

    private func makeImages(from data: Data) -> [CGImage]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let original = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        let input = CIImage(cgImage: original)
        let scaled = input.applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: 4.0,
            kCIInputAspectRatioKey: 1.0
        ])
        let gray = scaled.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.0,
                kCIInputContrastKey: 1.8,
                kCIInputBrightnessKey: 0.0
            ])
        let sharpened = gray.applyingFilter("CISharpenLuminance", parameters: [
            kCIInputSharpnessKey: 0.8
        ])
        let inverted = gray.applyingFilter("CIColorInvert")

        return [input, scaled, gray, sharpened, inverted].compactMap { image in
            context.createCGImage(image, from: image.extent.integral)
        }
    }

    private static func asASCIIDigit(_ character: Character) -> UnicodeScalar? {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first,
              (48...57).contains(scalar.value) else {
            return nil
        }
        return scalar
    }
}
