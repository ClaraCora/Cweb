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

    init(settings: SocksProxyValidationSettings = .defaults) {
        _draft = State(initialValue: settings.normalized)
    }

    var body: some View {
        Form {
            Section("结果处理") {
                Toggle("只保留可用代理", isOn: $draft.retainOnlyAvailable)

                Stepper(value: $draft.maxRetainedCount, in: 0...500) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("批量测试后最多保留")
                        Text(retentionDescription)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

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
                .foregroundStyle(.orange)
            }
            .textCase(nil)

            Section("测试性能") {
                Stepper(value: $draft.timeoutSeconds, in: 1...60) {
                    LabeledContent("单个代理超时") {
                        Text("\(draft.timeoutSeconds) 秒")
                            .monospacedDigit()
                    }
                }

                Stepper(value: $draft.maxConcurrent, in: 1...32) {
                    LabeledContent("最大并发数") {
                        Text("\(draft.maxConcurrent)")
                            .monospacedDigit()
                    }
                }

                Text("并发数越高，批量测试完成得越快，但可能增加网络和设备负载。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .textCase(nil)

            Section("测试目标") {
                TextField("测试主机", text: $draft.targetHost)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                TextField("测试端口", value: $draft.targetPort, format: .number)
                    .keyboardType(.numberPad)

                if !isValidTargetPort {
                    Label("端口必须是 1 到 65535 之间的数字。", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Toggle("验证 HTTPS / TLS", isOn: $draft.verifiesTLS)

                Text(tlsDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if !isValidTargetHost {
                    Label("请输入主机名或 IP 地址，不要包含路径、查询参数或空格。", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .textCase(nil)

            Section {
                Button("恢复默认设置", systemImage: "arrow.counterclockwise") {
                    showsResetConfirmation = true
                }
                .disabled(draft == SocksProxyValidationSettings.defaults)
            } footer: {
                Text("默认值：只保留可用代理、最多 30 个、按延迟排序，使用 example.com:443 并验证 TLS。数量限制只在下一次批量测试时生效。")
            }
        }
        .navigationTitle("SOCKS 验证设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    save()
                }
                .disabled(!hasChanges || !isValidTargetHost || !isValidTargetPort)
            }
        }
        .alert("恢复默认设置？", isPresented: $showsResetConfirmation) {
            Button("恢复", role: .destructive) {
                draft = .defaults
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
        draft.normalized != model.socksProxyValidationSettings.normalized
    }

    private var isValidTargetHost: Bool {
        let host = draft.targetHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty,
              host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              !host.contains(where: { "/?#".contains($0) }) else {
            return false
        }
        return true
    }

    private var isValidTargetPort: Bool {
        (1...65_535).contains(draft.targetPort)
    }

    private var retentionDescription: String {
        draft.maxRetainedCount == 0 ? "不限数量" : "最多 \(draft.maxRetainedCount) 个"
    }

    private var tlsDescription: String {
        draft.verifiesTLS
            ? "会通过代理完成真实 HTTPS/TLS 握手，能更接近浏览器实际访问。"
            : "只验证 SOCKS CONNECT，不执行 TLS 握手；可能保留无法打开 HTTPS 页面的节点。"
    }

    private func save() {
        do {
            try model.updateSocksProxyValidationSettings(draft.normalized)
            dismiss()
        } catch {
            presentedError = PresentedError(message: error.localizedDescription)
        }
    }
}
