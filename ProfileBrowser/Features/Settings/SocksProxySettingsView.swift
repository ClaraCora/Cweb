import SwiftUI

/// Settings for the user-initiated SOCKS validation pass. The view keeps a
/// local draft so cancelling a sheet/navigation transition never changes the
/// active policy halfway through editing.
@MainActor
struct SocksProxySettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var draft: SocksProxyValidationSettings
    @State private var presentedError: PresentedError?
    @State private var showsResetConfirmation = false
    @State private var retainedCountText: String
    @State private var timeoutText: String
    @State private var concurrentText: String

    init(settings: SocksProxyValidationSettings = .defaults) {
        _draft = State(initialValue: settings.normalized)
        _retainedCountText = State(initialValue: String(settings.normalized.maxRetainedCount))
        _timeoutText = State(initialValue: String(settings.normalized.timeoutSeconds))
        _concurrentText = State(initialValue: String(settings.normalized.maxConcurrent))
    }

    var body: some View {
        Form {
            Section("结果处理") {
                Toggle("只保留可用代理", isOn: $draft.retainOnlyAvailable)

                IntegerSettingField(title: "最多保留", text: $retainedCountText, range: 0...500, unit: "个")
                Text("0 表示不限数量；锁定代理始终保留。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Picker("编号顺序", selection: $draft.sortMode) {
                    ForEach(SocksProxySortMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Text(draft.sortMode.explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Label(
                    "环境保存的是显示编号。切换编号顺序后，已有环境可能会指向另一条代理。",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.footnote)
                .foregroundStyle(.primary)
            }
            .textCase(nil)

            Section("测试性能") {
                IntegerSettingField(title: "单个代理超时", text: $timeoutText, range: 1...60, unit: "秒")
                IntegerSettingField(title: "最大并发数", text: $concurrentText, range: 1...32, unit: "个")

                Text("并发数越高，批量测试完成得越快，但可能增加网络和设备负载。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .textCase(nil)

            Section("测试目标") {
                FormField("HTTPS 测速地址") {
                    TextField("https://www.gstatic.com/generate_204", text: $draft.targetURLString, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .lineLimit(1...3)
                }

                Toggle("验证 HTTPS / TLS", isOn: $draft.verifiesTLS)

                Text(tlsDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if !isValidTargetURL {
                    InlineValidationMessage(message: "请输入完整的 HTTPS 地址。")
                }
            }
            .textCase(nil)

            Section {
                Button("恢复默认设置", systemImage: "arrow.counterclockwise") {
                    showsResetConfirmation = true
                }
                .disabled(editedSettings == SocksProxyValidationSettings.defaults)
            } footer: {
                Text("默认值：只保留可用代理、最多 30 个、按延迟排序，使用 https://example.com/ 并验证 TLS。数量限制只在下一次批量测试时生效。")
            }
        }
        .navigationTitle("SOCKS 验证设置")
        .navigationBarTitleDisplayMode(.inline)
        .editorDismissProtection(isModified: hasChanges)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    save()
                }
                .disabled(!hasChanges || !isValidTargetURL || editedSettings == nil)
            }
        }
        .alert("恢复默认设置？", isPresented: $showsResetConfirmation) {
            Button("恢复", role: .destructive) {
                let defaults = SocksProxyValidationSettings.defaults
                draft = defaults
                retainedCountText = String(defaults.maxRetainedCount)
                timeoutText = String(defaults.timeoutSeconds)
                concurrentText = String(defaults.maxConcurrent)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前页面中的修改会被替换为默认值，点击“保存”后才会生效。")
        }
        .alert(item: $presentedError) { error in
            Alert(
                title: Text("保存失败"),
                message: Text(error.message),
                dismissButton: .default(Text("好"))
            )
        }
    }

    private var hasChanges: Bool {
        editedSettings != model.socksProxyValidationSettings.normalized
    }

    private var isValidTargetURL: Bool {
        SocksProxyValidationSettings.targetURL(from: draft.targetURLString) != nil
    }

    private var editedSettings: SocksProxyValidationSettings? {
        guard let count = Int(retainedCountText), (0...500).contains(count),
              let timeout = Int(timeoutText), (1...60).contains(timeout),
              let concurrent = Int(concurrentText), (1...32).contains(concurrent) else { return nil }
        var value = draft
        value.maxRetainedCount = count
        value.timeoutSeconds = timeout
        value.maxConcurrent = concurrent
        return value.normalized
    }

    private var tlsDescription: String {
        draft.verifiesTLS
            ? "会通过代理完成真实 HTTPS/TLS 握手，能更接近浏览器实际访问。"
            : "只验证 SOCKS CONNECT，不执行 TLS 握手；可能保留无法打开 HTTPS 页面的节点。"
    }

    private func save() {
        guard let editedSettings, isValidTargetURL else { return }
        do {
            try model.updateSocksProxyValidationSettings(editedSettings)
            dismiss()
        } catch {
            presentedError = PresentedError(message: error.localizedDescription)
        }
    }
}
