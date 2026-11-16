import Foundation

/// Domain-scoped selectors keep account actions separate from history,
/// navigation headings, search fields and unrelated amounts on the page.
struct WebsiteRule: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    var host: String
    var checkInContainerSelector = ""
    var actionSelector = ""
    var completionSelector = ""
    var failureSelector = ""
    var balanceSelector = ""
    var balanceReadySelector = ""
    var captchaSelector: String?
    var captchaAutoFillEnabled = false
    var captchaImageSelector: String?
    var captchaInputSelector: String?
    var captchaSubmitSelector: String?
    var captchaExpectedLength: Int?
    var environmentTimeoutSeconds: Int?
    var submissionTimeoutSeconds = 30

    var normalizedHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum WebsiteRuleError: LocalizedError {
    case invalidHost
    case invalidSelector(String)
    var errorDescription: String? {
        switch self {
        case .invalidHost: "请填写不重复的域名，例如 example.com，不含协议、端口和路径。"
        case .invalidSelector(let field): "\(field)的 CSS 选择器无效，请检查后重试。"
        }
    }
}

extension WebsiteRule {
    private enum CodingKeys: String, CodingKey {
        case id, host, checkInContainerSelector, actionSelector, completionSelector
        case failureSelector, balanceSelector, balanceReadySelector, captchaSelector
        case captchaAutoFillEnabled, captchaImageSelector, captchaInputSelector
        case captchaSubmitSelector, captchaExpectedLength, environmentTimeoutSeconds
        case submissionTimeoutSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        host = try container.decode(String.self, forKey: .host)
        checkInContainerSelector = try container.decodeIfPresent(String.self, forKey: .checkInContainerSelector) ?? ""
        actionSelector = try container.decodeIfPresent(String.self, forKey: .actionSelector) ?? ""
        completionSelector = try container.decodeIfPresent(String.self, forKey: .completionSelector) ?? ""
        failureSelector = try container.decodeIfPresent(String.self, forKey: .failureSelector) ?? ""
        balanceSelector = try container.decodeIfPresent(String.self, forKey: .balanceSelector) ?? ""
        balanceReadySelector = try container.decodeIfPresent(String.self, forKey: .balanceReadySelector) ?? ""
        captchaSelector = try container.decodeIfPresent(String.self, forKey: .captchaSelector)
        captchaAutoFillEnabled = try container.decodeIfPresent(Bool.self, forKey: .captchaAutoFillEnabled) ?? false
        captchaImageSelector = try container.decodeIfPresent(String.self, forKey: .captchaImageSelector)
        captchaInputSelector = try container.decodeIfPresent(String.self, forKey: .captchaInputSelector)
        captchaSubmitSelector = try container.decodeIfPresent(String.self, forKey: .captchaSubmitSelector)
        captchaExpectedLength = try container.decodeIfPresent(Int.self, forKey: .captchaExpectedLength)
        environmentTimeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .environmentTimeoutSeconds)
        submissionTimeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .submissionTimeoutSeconds) ?? 30
    }

    var selectors: [(String, String)] {
        [("签到区域", checkInContainerSelector), ("签到按钮", actionSelector),
         ("完成状态", completionSelector), ("失败状态", failureSelector),
         ("余额元素", balanceSelector), ("余额已加载标记", balanceReadySelector),
         ("验证码区域", captchaSelector ?? ""),
         ("验证码图片", captchaImageSelector ?? ""),
         ("验证码输入框", captchaInputSelector ?? ""),
         ("验证码提交控件", captchaSubmitSelector ?? "")]
    }
}
