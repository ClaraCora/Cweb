import SwiftUI

@MainActor
struct SocksProxyPresetEditorView: View {
    @Environment(\.dismiss) private var dismiss

    private let originalPreset: SocksProxyPreset?
    private let onSave: (SocksProxyPreset) throws -> Void

    @State private var name: String
    @State private var urlText: String
    @State private var isEnabled: Bool
    @State private var presentedError: PresentedError?

    init(
        preset: SocksProxyPreset? = nil,
        onSave: @escaping (SocksProxyPreset) throws -> Void
    ) {
        originalPreset = preset
        self.onSave = onSave
        _name = State(initialValue: preset?.name ?? "")
        _urlText = State(initialValue: preset?.url.absoluteString ?? "")
        _isEnabled = State(initialValue: preset?.isEnabled ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("预设信息") {
                    TextField("名称（可选）", text: $name)
                        .textInputAutocapitalization(.sentences)
                    TextField("https://example.com/proxies.txt", text: $urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("启用自动拉取", isOn: $isEnabled)
                }
            }
            .navigationTitle(originalPreset == nil ? "添加预设链接" : "编辑预设链接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", systemImage: "checkmark") { save() }
                        .disabled(!isValid)
                }
            }
            .alert(item: $presentedError) { error in
                Alert(
                    title: Text("无法保存"),
                    message: Text(error.message),
                    dismissButton: .default(Text("好"))
                )
            }
        }
    }

    private var validatedURL: URL? {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil else { return nil }
        return url
    }

    private var isValid: Bool { validatedURL != nil }

    private func save() {
        guard let url = validatedURL else {
            presentedError = PresentedError(message: "请输入有效的 HTTP 或 HTTPS 订阅链接。")
            return
        }

        let preset = SocksProxyPreset(
            id: originalPreset?.id ?? UUID(),
            name: name,
            url: url,
            isEnabled: isEnabled,
            createdAt: originalPreset?.createdAt ?? .now,
            updatedAt: .now
        )

        do {
            try onSave(preset)
            dismiss()
        } catch {
            presentedError = PresentedError(message: error.localizedDescription)
        }
    }
}

