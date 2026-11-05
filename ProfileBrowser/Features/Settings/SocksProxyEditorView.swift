import SwiftUI

/// Editing retains the record ID; copying keeps the entered values but saves
/// a new, untested record after the endpoint identity has changed.
@MainActor
struct SocksProxyEditorView: View {
    @Environment(\.dismiss) private var dismiss

    private let originalProxy: SocksProxy?
    private let isCopy: Bool
    private let onSave: (SocksProxy) throws -> Void

    @State private var code: String
    @State private var isLocked: Bool
    @State private var scheme: SocksProxyScheme
    @State private var host: String
    @State private var port: String
    @State private var username: String
    @State private var password: String
    @State private var presentedError: PresentedError?

    init(
        proxy: SocksProxy? = nil,
        isCopy: Bool = false,
        onSave: @escaping (SocksProxy) throws -> Void
    ) {
        originalProxy = proxy
        self.isCopy = isCopy
        self.onSave = onSave
        _code = State(initialValue: proxy?.displayCode ?? "")
        _isLocked = State(initialValue: isCopy ? false : (proxy?.isLocked ?? false))
        _scheme = State(initialValue: proxy?.scheme ?? .socks5)
        _host = State(initialValue: proxy?.host ?? "")
        _port = State(initialValue: proxy.map { String($0.port) } ?? "1080")
        _username = State(initialValue: proxy?.username ?? "")
        _password = State(initialValue: proxy?.password ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("标识") {
                    TextField("代号（可选）", text: $code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

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

                Section {
                    Toggle("锁定代理", isOn: $isLocked)
                } footer: {
                    Text("锁定后仍可编辑和测试，但不会被单独删除、批量删除、清空或验证结果裁剪。")
                }

                if let originalProxy, !isCopy {
                    Section("状态") {
                        LabeledContent("地址", value: originalProxy.displayAddress)
                        LabeledContent("可用性", value: statusText(originalProxy.latestStatus))
                        if let latency = originalProxy.latestLatency {
                            LabeledContent("延迟", value: "\(latency) ms")
                        }
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .editorDismissProtection(isModified: hasChanges)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { save() }
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
        SocksProxy.normalizeHost(host)
    }

    private var hasChanges: Bool {
        code != (originalProxy?.displayCode ?? "")
            || isLocked != (isCopy ? false : (originalProxy?.isLocked ?? false))
            || scheme != (originalProxy?.scheme ?? .socks5)
            || host != (originalProxy?.host ?? "")
            || port != (originalProxy.map { String($0.port) } ?? "1080")
            || username != (originalProxy?.username ?? "")
            || password != (originalProxy?.password ?? "")
    }

    private var navigationTitle: String {
        if isCopy { return "复制代理" }
        return originalProxy == nil ? "添加代理" : "编辑代理"
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
            id: isCopy ? UUID() : (originalProxy?.id ?? UUID()),
            code: code,
            isLocked: isLocked,
            scheme: scheme,
            host: normalizedHost,
            port: parsedPort,
            username: normalizedUsername.isEmpty ? nil : normalizedUsername,
            password: normalizedPassword,
            latencyMilliseconds: isCopy ? nil : originalProxy?.latencyMilliseconds,
            status: isCopy ? .untested : (originalProxy?.status ?? .untested),
            lastCheckedAt: isCopy ? nil : originalProxy?.lastCheckedAt,
            validationMessage: isCopy ? nil : originalProxy?.validationMessage,
            sourceURLString: originalProxy?.sourceURLString
        )
        proxy.sourceURLString = proxy.displayAddress
        if isCopy, proxy.identityKey == originalProxy?.identityKey {
            presentedError = PresentedError(
                message: "复制代理时，请修改主机、端口或用户名后再保存。"
            )
            return
        }

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
