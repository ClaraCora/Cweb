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
    var captchaAutoSubmitEnabled = false
    var captchaImageSelector: String?
    var captchaInputSelector: String?
    var captchaSubmitSelector: String?
    var captchaExpectedLength: Int?
    var environmentTimeoutSeconds: Int?
    var submissionTimeoutSeconds = 30

    var normalizedHost: String {
        Self.normalizeHost(host)
    }

    /// Website rules are scoped to a site, so a rule saved while logging in
    /// on `cf.example.com` also applies after the site redirects to
    /// `www.example.com`. Exact host matching made this fail for sites that
    /// use separate CDN and application subdomains.
    func matches(host candidate: String) -> Bool {
        Self.sameSite(normalizedHost, candidate)
    }

    static func normalizeHost(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    static func sameSite(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalizeHost(lhs)
        let right = normalizeHost(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        guard left != right else { return true }

        // Keep IP addresses and localhost exact-only. For host names, use a
        // small public-suffix approximation that covers common two-label
        // suffixes without introducing a runtime dependency.
        guard left.contains("."), right.contains("."),
              !left.isIPAddress, !right.isIPAddress else { return false }
        return registrableDomain(left) == registrableDomain(right)
    }

    private static func registrableDomain(_ host: String) -> String {
        let labels = host.split(separator: ".").map(String.init)
        guard labels.count >= 2 else { return host }
        let suffix = labels.suffix(2).joined(separator: ".")
        let commonSecondLevelSuffixes = Set(["co.uk", "org.uk", "ac.uk", "gov.uk", "com.au", "net.au", "org.au", "co.jp", "com.cn", "net.cn", "org.cn"])
        let count = commonSecondLevelSuffixes.contains(suffix) ? 3 : 2
        return labels.suffix(min(count, labels.count)).joined(separator: ".")
    }
}

private extension String {
    var isIPAddress: Bool {
        let parts = split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { Int($0) != nil && (0...255).contains(Int($0)!) }
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
        case captchaAutoFillEnabled, captchaAutoSubmitEnabled, captchaImageSelector, captchaInputSelector
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
        captchaAutoSubmitEnabled = try container.decodeIfPresent(Bool.self, forKey: .captchaAutoSubmitEnabled) ?? false
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
