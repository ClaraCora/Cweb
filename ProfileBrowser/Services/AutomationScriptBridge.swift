import CoreGraphics
import Foundation
import ImageIO
import Vision
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
            window.CwebSiteRule = __cwebRules.find(rule =>
                rule.host.trim().toLowerCase() === window.location.hostname.toLowerCase()) || {};
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
            const __cwebExplicitMatches = __cwebMatches.filter(p => p !== '*://*/*' && p !== '<all_urls>');
            const __cwebAllowed = __cwebExplicitMatches.length > 0
                ? __cwebExplicitMatches.some(__cwebMatchesPage)
                : !__cwebHomeOrigin || window.location.origin === __cwebHomeOrigin
                    || __cwebRules.some(r => r.host.trim().toLowerCase() === window.location.hostname.toLowerCase());
            if (!__cwebAllowed || (__cwebMatches.length > 0
                && !__cwebMatches.some(__cwebMatchesPage))) {
                return;
            }

            let __cwebPaused = Boolean(window.__cwebAutomationManuallyPaused) || __cwebIsPausedPersisted();
            const __cwebSent = new Set();
            let __cwebCaptchaInput = null;
            let __cwebCaptchaSubmit = null;
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
                    __cwebPaused = true;
                    try {
                        if (__cwebPauseKey) {
                            window.localStorage.setItem(__cwebPauseKey, "1");
                        }
                    } catch (_) {}
                    __cwebPost("captcha", message, details);
                },
                fillCaptcha: (code) => {
                    const value = String(code || "").replace(/[^0-9]/g, "");
                    if (!value || !__cwebCaptchaInput || !__cwebCaptchaInput.isConnected) return false;
                    __cwebCaptchaInput.focus({ preventScroll: true });
                    const prototype = Object.getPrototypeOf(__cwebCaptchaInput);
                    const descriptor = Object.getOwnPropertyDescriptor(prototype, "value");
                    if (descriptor?.set) descriptor.set.call(__cwebCaptchaInput, value);
                    else __cwebCaptchaInput.value = value;
                    __cwebCaptchaInput.dispatchEvent(new Event("input", { bubbles: true }));
                    __cwebCaptchaInput.dispatchEvent(new Event("change", { bubbles: true }));
                    if (__cwebCaptchaSubmit?.isConnected) __cwebCaptchaSubmit.click();
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
    case needsManual

    var message: String? {
        switch self {
        case .idle: nil
        case .recognizing: "正在识别验证码…"
        case .filled: "验证码已填入，正在继续检测。"
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
        guard let image = makeImage(from: imageData) else {
            return .unavailable("无法读取验证码图片")
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.01

        do {
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])
        } catch {
            return .unavailable("验证码识别失败")
        }

        let observations = (request.results ?? []).sorted {
            if abs($0.boundingBox.minY - $1.boundingBox.minY) > 0.05 {
                return $0.boundingBox.minY > $1.boundingBox.minY
            }
            return $0.boundingBox.minX < $1.boundingBox.minX
        }
        guard !observations.isEmpty else {
            return .unavailable("未识别到数字")
        }

        var confidenceTotal = 0.0
        var confidenceCount = 0
        var rawText = ""
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            rawText += candidate.string
            confidenceTotal += Double(candidate.confidence)
            confidenceCount += 1
        }

        let invalidCharacters = rawText.filter { !$0.isWhitespace && !$0.isNumber }
        guard invalidCharacters.isEmpty else {
            return .unavailable("识别结果包含非数字字符")
        }

        let code = rawText.compactMap(Self.asASCIIDigit).map(String.init).joined()
        let validLength: Bool
        if let expectedLength {
            validLength = code.count == expectedLength
        } else {
            validLength = (4...8).contains(code.count)
        }
        guard validLength else {
            return .unavailable("识别结果长度不符合验证码规则")
        }

        let confidence = confidenceCount == 0 ? 0 : confidenceTotal / Double(confidenceCount)
        guard confidence >= 0.80 else {
            return .unavailable("识别置信度不足")
        }
        return .recognized(code: code, confidence: confidence)
    }

    private func makeImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let original = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        let input = CIImage(cgImage: original)
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.0,
                kCIInputContrastKey: 1.35,
                kCIInputBrightnessKey: 0.02
            ])
        let scale = original.width < 480 ? 2.0 : 1.0
        let scaled = scale == 1.0
            ? input
            : input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let extent = scaled.extent.integral
        return context.createCGImage(scaled, from: extent)
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
