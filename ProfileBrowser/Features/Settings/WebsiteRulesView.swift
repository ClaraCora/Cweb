import SwiftUI

@MainActor
struct WebsiteRulesView: View {
    @Environment(AppModel.self) private var model
    @State private var rules: [WebsiteRule] = []
    @State private var loaded = false
    @State private var error: PresentedError?

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
                    Stepper("提交超时：\(rule.submissionTimeoutSeconds) 秒", value: $rule.submissionTimeoutSeconds, in: 5...120, step: 5)
                    Button("删除此网站规则", role: .destructive) { rules.removeAll { $0.id == rule.id } }
                }
            }
            Button("添加网站", systemImage: "plus") { rules.append(WebsiteRule(host: "")) }
        }
        .navigationTitle("网站识别规则")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .editorDismissProtection(isModified: rules != (model.globalScriptSettings.siteRules ?? []))
        .task {
            guard !loaded else { return }
            rules = model.globalScriptSettings.siteRules ?? []
            loaded = true
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    do { try model.updateWebsiteRules(rules) }
                    catch { self.error = PresentedError(message: error.localizedDescription) }
                }
                .disabled(rules == (model.globalScriptSettings.siteRules ?? []))
            }
        }
        .alert(item: $error) { Alert(title: Text("无法保存规则"), message: Text($0.message)) }
    }

    private func selector(_ title: String, text: Binding<String>) -> some View {
        FormField(title) {
            TextField(title, text: text, axis: .vertical)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
        }
    }
}
