import SwiftUI

/// Editor for one SOCKS proxy record. The record ID is retained when editing
/// so profiles that reference the current ranking can continue to use it.
@MainActor
struct SocksProxyEditorView: View {
    @Environment(\.dismiss) private var dismiss

    private let originalProxy: SocksProxy?
    private let onSave: (SocksProxy) throws -> Void

    @State private var scheme: SocksProxyScheme
    @State private var host: String
    @State private var port: String
    @State private var username: String
    @State private var password: String
    @State private var presentedError: PresentedError?

    init(
        proxy: SocksProxy? = nil,
        onSave: @escaping (SocksProxy) throws -> Void
    ) {
        originalProxy = proxy
        self.onSave = onSave
        _scheme = State(initialValue: proxy?.scheme ?? .socks5)
        _host = State(initialValue: proxy?.host ?? "")
        _port = State(initialValue: proxy.map { String($0.port) } ?? "1080")
        _username = State(initialValue: proxy?.username ?? "")
        _password = State(initialValue: proxy?.password ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("代理地址") {
                    Picker("协议", selection: $scheme) {
                        ForEach(SocksProxyScheme.allCases, id: \.self) { value in
                            Text(value.rawValue.uppercased()).tag(value)
                        }
                    }
                    .pickerStyle(.menu)

                    TextField("主机名或 IP 地址", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    TextField("端口", text: $port)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("认证（可选）") {
                    TextField("用户名", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("密码", text: $password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if let originalProxy {
                    Section("状态") {
                        LabeledContent("地址", value: originalProxy.displayAddress)
                        LabeledContent("可用性", value: statusText(originalProxy.status))
                        if let latency = originalProxy.latencyMilliseconds {
                            LabeledContent("延迟", value: "\(latency) ms")
                        }
                    }
                }
            }
            .navigationTitle(originalProxy == nil ? "添加代理" : "编辑代理")
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

    private var normalizedHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedPort: Int? {
        guard let value = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...65_535).contains(value) else { return nil }
        return value
    }

    private var isValid: Bool {
        hostIsValid && parsedPort != nil && authFieldsValid
    }

    private var hostIsValid: Bool {
        !normalizedHost.isEmpty
            && normalizedHost.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
            && !normalizedHost.contains(where: { "/?#".contains($0) })
    }

    private var authFieldsValid: Bool {
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedUsername.isEmpty == password.isEmpty { return true }
        // Leaving the password blank while keeping the same username means
        // "retain the existing keychain value" when editing a record.
        return password.isEmpty && normalizedUsername == (originalProxy?.username ?? "")
    }

    private func save() {
        guard hostIsValid else {
            presentedError = PresentedError(message: "请输入有效的主机名或 IP 地址。")
            return
        }
        guard let parsedPort else {
            presentedError = PresentedError(message: "端口必须是 1 到 65535 之间的数字。")
            return
        }
        guard authFieldsValid else {
            presentedError = PresentedError(message: "用户名和密码需要同时填写，或都留空。")
            return
        }

        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPassword: String?
        if !password.isEmpty {
            normalizedPassword = password
        } else if normalizedUsername == (originalProxy?.username ?? "") {
            // A blank password while editing keeps the existing keychain
            // credential. Clearing the username intentionally clears auth.
            normalizedPassword = originalProxy?.password
        } else {
            normalizedPassword = nil
        }
        var proxy = SocksProxy(
            id: originalProxy?.id ?? UUID(),
            scheme: scheme,
            host: normalizedHost,
            port: parsedPort,
            username: normalizedUsername.isEmpty ? nil : normalizedUsername,
            password: normalizedPassword,
            latencyMilliseconds: originalProxy?.latencyMilliseconds,
            status: originalProxy?.status ?? .untested,
            lastCheckedAt: originalProxy?.lastCheckedAt,
            validationMessage: originalProxy?.validationMessage,
            sourceURLString: originalProxy?.sourceURLString
        )
        proxy.sourceURLString = proxy.displayAddress

        do {
            try onSave(proxy)
            dismiss()
        } catch {
            presentedError = PresentedError(message: error.localizedDescription)
        }
    }

    private func statusText(_ status: SocksProxyStatus) -> String {
        switch status {
        case .untested: "未验证"
        case .available: "可用"
        case .unavailable: "不可用"
        }
    }
}
