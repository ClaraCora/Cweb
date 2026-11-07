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
    var selectors: [(String, String)] {
        [("签到区域", checkInContainerSelector), ("签到按钮", actionSelector),
         ("完成状态", completionSelector), ("失败状态", failureSelector),
         ("余额元素", balanceSelector), ("余额已加载标记", balanceReadySelector),
         ("验证码区域", captchaSelector ?? "")]
    }
}
