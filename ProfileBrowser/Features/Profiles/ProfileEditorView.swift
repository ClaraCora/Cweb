import SwiftUI

@MainActor
struct ProfileEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private let originalProfile: BrowserProfile?
    private let onSave: (ProfileEditorSubmission) throws -> Void

    @State private var name: String
    @State private var groupName: String
    @State private var homePageText: String
    @State private var userAgent: String
    @State private var selectedUserAgentName: String?
    @State private var autofillUsername: String
    @State private var autofillPassword: String
    @State private var socksProxyNumber: Int?
    @State private var color: ProfileColor
    @State private var localError: PresentedError?

    init(
        profile: BrowserProfile?,
        defaultGroupName: String? = nil,
        onSave: @escaping (ProfileEditorSubmission) throws -> Void
    ) {
        self.originalProfile = profile
        self.onSave = onSave
        _name = State(initialValue: profile?.name ?? "")
        _groupName = State(initialValue: profile?.groupName ?? defaultGroupName ?? "")
        _homePageText = State(initialValue: profile?.homePage.absoluteString ?? BrowserProfile.defaultHomePage.absoluteString)
        _userAgent = State(initialValue: profile?.userAgent ?? BrowserProfile.defaultUserAgent)
        _selectedUserAgentName = State(initialValue: BrowserProfile.userAgentPresetName(for: profile?.userAgent))
        _autofillUsername = State(initialValue: "")
        _autofillPassword = State(initialValue: "")
        _socksProxyNumber = State(initialValue: profile?.socksProxyNumber)
        _color = State(initialValue: profile?.color ?? .indigo)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("环境名称", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField("分组（可选）", text: $groupName)
                        .textInputAutocapitalization(.words)
                    TextField("主页网址", text: $homePageText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("标识颜色") {
                    HStack(spacing: 8) {
                        ForEach(ProfileColor.allCases) { option in
                            Button {
                                color = option
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(option.color)
                                        .frame(width: 30, height: 30)
                                    if color == option {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                                .frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.title)
                            .accessibilityValue(color == option ? "已选择" : "未选择")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Section("User-Agent") {
                    TextField("User-Agent", text: $userAgent, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(3...6)
                        .font(.caption.monospaced())

                    Button {
                        userAgent = BrowserProfile.defaultUserAgent
                        selectedUserAgentName = "iPhone Safari"
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("恢复 iPhone Safari 默认值")
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.accentColor)
                    Button {
                        userAgent = BrowserProfile.randomUserAgent(for: selectedUserAgentName)
                    } label: {
                        HStack {
                            Image(systemName: "shuffle")
                            Text("随机生成当前浏览器 UA")
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.accentColor)
                    Menu {
                        ForEach(BrowserProfile.userAgentPresets) { preset in
                            Button(preset.name) {
                                selectedUserAgentName = preset.name
                                userAgent = preset.value
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "list.bullet")
                            Text("选择浏览器 UA")
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.accentColor)
                }

                Section("SOCKS 代理") {
                    Picker(
                        "代理编号",
                        selection: Binding(
                            get: { socksProxyNumber ?? 0 },
                            set: { socksProxyNumber = $0 == 0 ? nil : $0 }
                        )
                    ) {
                        Text("不使用代理").tag(0)
                        ForEach(rankedProxyOptions) { option in
                            Text("第 \(option.number) 号 · \(option.proxy.displayCode ?? option.proxy.displayAddress)")
                                .tag(option.number)
                        }
                    }
                    .pickerStyle(.menu)

                    if let socksProxyNumber {
                        if let proxy = model.socksProxy(forDisplayNumber: socksProxyNumber) {
                            if let code = proxy.displayCode {
                                LabeledContent("代号", value: code)
                            }
                            LabeledContent("当前代理", value: proxy.displayAddress)
                        } else {
                            Text("当前没有第 \(socksProxyNumber) 号代理，重新拉取或验证后会按这个编号使用。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("环境保存的是当前显示编号。代理验证或拉取后重新排序时，同一编号会指向新的代理内容。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("自动填充") {
                    TextField("账号（可选）", text: $autofillUsername)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("密码（可选）", text: $autofillPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("填写账号和密码后，会安全保存到钥匙串，并可在浏览器的凭据入口中填充。编辑已有环境时留空会保留原凭据。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(originalProfile == nil ? "新建环境" : "编辑环境")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", systemImage: "xmark") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", systemImage: "checkmark") {
                        save()
                    }
                    .disabled(!isValid)
                }
            }
            .alert(item: $localError) { error in
                Alert(
                    title: Text("无法保存"),
                    message: Text(error.message),
                    dismissButton: .default(Text("好"))
                )
            }
        }
    }

    private var validatedHomePage: URL? {
        let trimmed = homePageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(),
            scheme == "https" || scheme == "http",
            url.host != nil
        else {
            return nil
        }
        return url
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !userAgent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && validatedHomePage != nil
            && autofillFieldsValid
    }

    private var autofillFieldsValid: Bool {
        autofillUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == autofillPassword.isEmpty
    }

    private func save() {
        guard let homePage = validatedHomePage else {
            localError = PresentedError(message: "主页必须是有效的 HTTP 或 HTTPS 网址。")
            return
        }
        guard autofillFieldsValid else {
            localError = PresentedError(message: "自动填充账号和密码需要同时填写，或都留空。")
            return
        }

        do {
            if var profile = originalProfile {
                profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedGroupName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
                profile.groupName = trimmedGroupName.isEmpty ? nil : trimmedGroupName
                profile.homePage = homePage
                profile.userAgent = userAgent.trimmingCharacters(in: .whitespacesAndNewlines)
                profile.color = color
                profile.socksProxyNumber = socksProxyNumber
                try onSave(.update(
                    profile,
                    autofillUsername: autofillUsername,
                    autofillPassword: autofillPassword
                ))
            } else {
                try onSave(.create(
                    name: name,
                    groupName: groupName,
                    homePage: homePage,
                    userAgent: userAgent,
                    color: color,
                    socksProxyNumber: socksProxyNumber,
                    autofillUsername: autofillUsername,
                    autofillPassword: autofillPassword
                ))
            }
            dismiss()
        } catch {
            localError = PresentedError(message: error.localizedDescription)
        }
    }

    private var rankedProxyOptions: [SocksProxyRanking] {
        model.rankedSocksProxies
    }
}

enum ProfileEditorSubmission {
    case create(
        name: String,
        groupName: String,
        homePage: URL,
        userAgent: String,
        color: ProfileColor,
        socksProxyNumber: Int?,
        autofillUsername: String,
        autofillPassword: String
    )
    case update(BrowserProfile, autofillUsername: String, autofillPassword: String)
}
