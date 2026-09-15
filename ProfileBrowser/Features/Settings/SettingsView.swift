import SwiftUI

/// The single entry point for SOCKS and app-level preferences.
@MainActor
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppSettings.appearanceModeKey) private var appearanceModeRaw = AppSettings.defaultAppearanceMode
    @State private var showsBackup = false
    @State private var scriptDraft = GlobalScriptSettings.default
    @State private var hasLoadedScript = false
    @State private var presentedError: PresentedError?

    private var appearanceMode: Binding<AppAppearanceMode> {
        Binding(
            get: { AppAppearanceMode(rawValue: appearanceModeRaw) ?? .system },
            set: { appearanceModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("外观") {
                Picker("配色模式", selection: appearanceMode) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }

            Section {
                Toggle("启用签到脚本", isOn: $scriptDraft.enabled)

                Label(
                    scriptDraft.enabled ? "已启用，进入环境后运行" : "当前关闭",
                    systemImage: scriptDraft.enabled ? "checkmark.circle.fill" : "pause.circle"
                )
                .foregroundStyle(scriptDraft.enabled ? .green : .secondary)

                FormField("脚本内容") {
                    TextEditor(text: $scriptDraft.source)
                        .font(.system(.footnote, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .frame(minHeight: 260, maxHeight: 460)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                if scriptDraft.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    InlineValidationMessage(message: "脚本为空，开启后不会执行自动签到。")
                }

                Button("恢复默认模板", systemImage: "arrow.counterclockwise") {
                    scriptDraft.source = GlobalScriptSettings.default.source
                }

                if let result = model.lastAutomationResult {
                    let profileName = model.profiles.first(where: { $0.id == result.profileID })?.name ?? "已删除环境"
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("最近结果：\(result.message.isEmpty ? result.kind.title : result.message)")
                            Text("\(profileName) · \(result.date, style: .relative)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: result.kind.systemImage)
                            .foregroundStyle(result.kind.tint)
                    }
                }
            } header: {
                Text("全局签到脚本")
            } footer: {
                Text("脚本只在进入环境后运行，并可读取当前网页内容。可调用 window.CwebCheckIn.success(...) 或 captchaDetected(...) 上报结果。检测到验证码时会暂停，需你手动完成。修改保存后，新进入的环境才会使用最新脚本。")
            }
            .textCase(nil)

            Section {
                NavigationLink {
                    SocksProxySettingsView(settings: model.socksProxyValidationSettings)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("验证与保留规则")
                            Text(proxyPolicySummary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(.tint)
                    }
                }
                .foregroundStyle(.primary)
            } header: {
                Text("代理策略")
            }

            Section("数据") {
                Button {
                    showsBackup = true
                } label: {
                    Label("加密备份", systemImage: "lock.doc")
                }
            }

            Section("关于") {
                HStack(spacing: 16) {
                    Image(systemName: "safari.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.tint)
                        .frame(width: 56, height: 56)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("环境浏览器")
                            .font(.headline)
                        Text("Cweb")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
                LabeledContent("版本") {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("构建") {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.large)
        .editorDismissProtection(isModified: hasScriptChanges)
        .task {
            guard !hasLoadedScript else { return }
            scriptDraft = model.globalScriptSettings
            hasLoadedScript = true
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    saveScript()
                }
                .disabled(!hasScriptChanges)
            }
        }
        .sheet(isPresented: $showsBackup) {
            BackupView()
        }
        .alert(item: $presentedError) { error in
            Alert(
                title: Text("保存失败"),
                message: Text(error.message),
                dismissButton: .default(Text("好"))
            )
        }
    }

    private var proxyPolicySummary: String {
        let settings = model.socksProxyValidationSettings
        let count = settings.maxRetainedCount == 0
            ? "不限保留数量"
            : "最多保留 \(settings.maxRetainedCount) 个"
        return "\(settings.sortMode.title) · \(count)"
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
        case .success: .green
        case .captcha: .orange
        case .error: .red
        case .noButton, .resume: .secondary
        }
    }
}
