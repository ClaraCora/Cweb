import Foundation
import WebKit

@MainActor
enum WebsiteRuleValidator {
    static func validateDelimiters(_ selector: String, field: String) throws {
        var stack: [Character] = []
        var quote: Character?
        var escaped = false
        for character in selector {
            if escaped { escaped = false; continue }
            if character == "\\" { escaped = true; continue }
            if let current = quote { if character == current { quote = nil }; continue }
            if character == "\"" || character == "'" { quote = character; continue }
            if character == "[" || character == "(" { stack.append(character) }
            if character == "]" || character == ")" {
                guard stack.popLast() == (character == "]" ? "[" : "(") else { throw WebsiteRuleError.invalidSelector(field) }
            }
        }
        guard stack.isEmpty, quote == nil, !escaped else { throw WebsiteRuleError.invalidSelector(field) }
    }

    static func validate(_ rules: [WebsiteRule]) async throws {
        let page = WebPage()
        defer { page.stopLoading() }
        try await BoundedOperation.run(timeout: .seconds(5)) {
            for try await _ in page.load(html: "<html><body></body></html>") { }
            for rule in rules {
                for (field, selector) in rule.selectors where !selector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let valid = try await page.callJavaScript(
                        "try { document.querySelectorAll(selector); return true; } catch (_) { return false; }",
                        arguments: ["selector": selector]) as? Bool
                    guard valid == true else { throw WebsiteRuleError.invalidSelector(field) }
                }
            }
        }
    }
}
