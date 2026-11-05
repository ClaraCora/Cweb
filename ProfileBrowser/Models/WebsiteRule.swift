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
    var submissionTimeoutSeconds = 30

    var normalizedHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum WebsiteRuleError: LocalizedError {
    case invalidHost
    var errorDescription: String? { "请填写不重复的域名，例如 example.com，不含协议、端口和路径。" }
}
