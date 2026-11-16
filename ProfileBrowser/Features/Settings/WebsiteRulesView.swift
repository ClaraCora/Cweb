import SwiftUI

@MainActor
struct WebsiteRulesView: View {
    @Environment(AppModel.self) private var model
    @State private var rules: [WebsiteRule] = []
    @State private var loaded = false
    @State private var initialRules: [WebsiteRule] = []
    @State private var error: PresentedError?
    @State private var isSaving = false
    @State private var status: String?
    @State private var testResults: [UUID: String] = [:]
    let session: BrowserSession?

    init(session: BrowserSession? = nil) { self.session = session }

    var body: some View {
        Form {
            Section {
                Text("按域名限定签到区域和金额来源，避免将历史记录或其他金额误认。留空的选择器使用通用检测。自定义脚本可读取 window.CwebSiteRule。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach($rules) { $rule in
                Section(rule.host.isEmpty ? "新网站" : rule.host) {
                    selector("域名", text: $rule.host)
                    selector("签到区域", text: $rule.checkInContainerSelector)
                    selector("签到按钮", text: $rule.actionSelector)
                    selector("完成状态", text: $rule.completionSelector)
                    selector("失败状态", text: $rule.failureSelector)
                    selector("余额元素", text: $rule.balanceSelector)
                    selector("余额已加载标记", text: $rule.balanceReadySelector)
                    selector("验证码区域", text: Binding(get: { rule.captchaSelector ?? "" }, set: { rule.captchaSelector = $0 }))
                    Toggle("启用数字验证码自动识别", isOn: $rule.captchaAutoFillEnabled)
                    Text("仅处理普通数字图片验证码。reCAPTCHA、hCaptcha、Turnstile、滑块和点选验证仍需手动完成。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    selector("验证码图片", text: Binding(get: { rule.captchaImageSelector ?? "" }, set: { rule.captchaImageSelector = $0 }))
                    selector("验证码输入框", text: Binding(get: { rule.captchaInputSelector ?? "" }, set: { rule.captchaInputSelector = $0 }))
                    selector("验证码提交控件（可选）", text: Binding(get: { rule.captchaSubmitSelector ?? "" }, set: { rule.captchaSubmitSelector = $0 }))
                    Stepper {
                        Text("验证码长度：\(rule.captchaExpectedLength.map(String.init) ?? "自动")")
                    } onIncrement: {
                        rule.captchaExpectedLength = min(8, (rule.captchaExpectedLength ?? 3) + 1)
                    } onDecrement: {
                        guard let length = rule.captchaExpectedLength else { return }
                        rule.captchaExpectedLength = length <= 4 ? nil : length - 1
                    }
                    Stepper("环境等待上限：\(rule.environmentTimeoutSeconds ?? 60) 秒", value: Binding(
                        get: { rule.environmentTimeoutSeconds ?? 60 }, set: { rule.environmentTimeoutSeconds = $0 }), in: 15...300, step: 15)
                    if let session, session.currentOrigin?.host == rule.normalizedHost {
                        Button("测试当前页面（不执行签到）") {
                            let snapshot = rule
                            Task { await test(snapshot, in: session) }
                        }
                        if let result = testResults[rule.id] { Text(result).font(.footnote).textSelection(.enabled) }
                    }
                    Stepper("提交超时：\(rule.submissionTimeoutSeconds) 秒", value: $rule.submissionTimeoutSeconds, in: 5...120, step: 5)
                    Button("删除此网站规则", role: .destructive) { rules.removeAll { $0.id == rule.id } }
                }
            }
            Button("添加网站", systemImage: "plus") { rules.append(WebsiteRule(host: session?.currentOrigin?.host ?? "")) }
            if rules == (model.globalScriptSettings.siteRules ?? []), let status { Text(status).font(.footnote).foregroundStyle(.secondary) }
            if session == nil { Text("可在浏览器的“更多 → 网站识别规则”中测试当前页面的匹配数量和金额。").font(.footnote).foregroundStyle(.secondary) }
        }
        .disabled(isSaving)
        .navigationTitle("网站识别规则")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .editorDismissProtection(isModified: rules != initialRules, isBusy: isSaving)
        .task {
            guard !loaded else { return }
            rules = model.globalScriptSettings.siteRules ?? []
            if let host = session?.currentOrigin?.host, !rules.contains(where: { $0.normalizedHost == host }) {
                rules.append(WebsiteRule(host: host))
            }
            initialRules = rules
            loaded = true
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    isSaving = true
                    let snapshot = rules
                    Task {
                        defer { isSaving = false }
                        do {
                            try await WebsiteRuleValidator.validate(snapshot)
                            try model.updateWebsiteRules(snapshot)
                            rules = model.globalScriptSettings.siteRules ?? []
                            initialRules = rules
                            status = "已保存，下次进入环境或新任务生效。"
                        } catch { self.error = PresentedError(message: error.localizedDescription) }
                    }
                }
                .disabled(isSaving || rules == (model.globalScriptSettings.siteRules ?? []))
            }
        }
        .alert(item: $error) { Alert(title: Text("无法保存规则"), message: Text($0.message)) }
    }

    private func test(_ rule: WebsiteRule, in session: BrowserSession) async {
        do {
            let origin = session.currentOrigin
            let result = try await BoundedOperation.run(timeout: .seconds(5)) {
                let documentID = try await session.page.callJavaScript("return window.__cwebDocumentID || ''; ") as? String
                var lines: [String] = []
                for (field, selector) in rule.selectors where !selector.isEmpty {
                    let count = try await session.page.callJavaScript(
                        "try { return document.querySelectorAll(selector).length; } catch (_) { return -1; }", arguments: ["selector": selector]) as? Int ?? -1
                    guard count >= 0 else { throw WebsiteRuleError.invalidSelector(field) }
                    lines.append("\(field)：匹配 \(count) 个")
                }
                let balance = try await session.readAccountBalanceResult(rule: rule)
                lines.append(balance.map { "读取金额：" + $0.value } ?? "余额尚未就绪或存在冲突")
                let currentID = try await session.page.callJavaScript("return window.__cwebDocumentID || ''; ") as? String
                guard !session.isClosed, session.currentOrigin == origin, currentID == documentID else {
                    throw BrowserSessionDiagnosticError(message: "页面已变化，请重新测试。")
                }
                return lines.joined(separator: "\n")
            }
            testResults[rule.id] = result
        } catch { testResults[rule.id] = error.localizedDescription }
    }

    private func selector(_ title: String, text: Binding<String>) -> some View {
        FormField(title) {
            TextField(title, text: text, axis: .vertical)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
        }
    }
}
