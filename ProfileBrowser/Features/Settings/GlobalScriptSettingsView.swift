import SwiftUI

@MainActor
struct GlobalScriptSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var scriptDraft = GlobalScriptSettings.default
    @State private var hasLoadedScript = false
    @State private var presentedError: PresentedError?
    @State private var confirmsReset = false
    @State private var previousSource: String?
    @State private var saveFeedback: String?

    var body: some View {
        Form {
            Section {
                NavigationLink("网站识别规则") { WebsiteRulesView() }
            }
            Section {
                Toggle("进入环境时自动运行", isOn: $scriptDraft.enabled)

                FormField("脚本内容") {
                    TextEditor(text: $scriptDraft.source)
                        .font(.system(.footnote, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .accessibilityLabel("脚本内容")
                        .frame(minHeight: 260, maxHeight: 460)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                if scriptDraft.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    InlineValidationMessage(message: "脚本为空，开启后不会执行自动签到。")
                }

                Button("恢复默认模板", systemImage: "arrow.counterclockwise") {
                    confirmsReset = true
                }

                if let previousSource {
                    Button("撤销恢复模板") { scriptDraft.source = previousSource; self.previousSource = nil }
                }
                if !hasScriptChanges, let saveFeedback { Text(saveFeedback).font(.footnote).foregroundStyle(AppUI.secondaryText) }
                if let result = model.lastAutomationResult {
                    let profileName = model.profiles.first(where: { $0.id == result.profileID })?.name ?? "已删除环境"
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("最近结果：\(result.message.isEmpty ? result.kind.title : result.message)")
                            Text("\(profileName) · \(result.date, style: .relative)")
                                .font(.footnote)
                                .foregroundStyle(AppUI.secondaryText)
                        }
                    } icon: {
                        Image(systemName: result.kind.systemImage)
                            .foregroundStyle(result.kind.tint)
                    }
                }
            } header: {
                Text("全局签到脚本")
            } footer: {
                Text("分组顶部的“开始”会为本次任务启用脚本，不受上方开关影响。脚本可读取当前网页，通过 window.CwebCheckIn.success(...) 或 captchaDetected(...) 上报结果。检测到验证码时暂停当前环境，请在网页中手动输入并完成验证，再点击“继续检测”；等待期间不会跳过当前环境。修改保存后，新任务才会使用最新脚本。")
            }
            .textCase(nil)
        }
        .navigationTitle("签到脚本")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .editorDismissProtection(isModified: hasScriptChanges)
        .task {
            guard !hasLoadedScript else { return }
            scriptDraft = model.globalScriptSettings
            hasLoadedScript = true
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { saveScript() }
                    .disabled(!hasScriptChanges)
            }
        }
        .confirmationDialog("替换当前脚本为默认模板？", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("恢复模板") { previousSource = scriptDraft.source; scriptDraft.source = GlobalScriptSettings.default.source }
            Button("取消", role: .cancel) {}
        }
        .alert(item: $presentedError) { error in
            Alert(title: Text("保存失败"), message: Text(error.message), dismissButton: .default(Text("好")))
        }
    }

    private var hasScriptChanges: Bool {
        scriptDraft.enabled != model.globalScriptSettings.enabled
            || scriptDraft.source != model.globalScriptSettings.source
    }

    private func saveScript() {
        do {
            try model.updateGlobalScriptSettings(
                enabled: scriptDraft.enabled,
                source: scriptDraft.source
            )
            scriptDraft = model.globalScriptSettings
            saveFeedback = "已保存，下次进入环境或新任务生效。"
        } catch {
            presentedError = PresentedError(message: error.localizedDescription)
        }
    }
}

private extension AutomationEventKind {
    var title: String {
        switch self {
        case .success: "签到成功"
        case .captcha: "等待验证码"
        case .noButton: "未找到签到入口"
        case .error: "脚本异常"
        case .resume: "已恢复检测"
        }
    }

    var systemImage: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .captcha: "hand.raised.fill"
        case .noButton: "questionmark.circle"
        case .error: "exclamationmark.triangle.fill"
        case .resume: "arrow.triangle.2.circlepath"
        }
    }

    var tint: Color {
        switch self {
        case .success: AppUI.success
        case .captcha, .noButton: AppUI.warning
        case .error: AppUI.danger
        case .resume: AppUI.secondaryText
        }
    }
}
