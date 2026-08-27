import SwiftUI

@MainActor
struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss

    private let originalProfile: BrowserProfile?
    private let onSave: (ProfileEditorSubmission) throws -> Void

    @State private var name: String
    @State private var groupName: String
    @State private var homePageText: String
    @State private var userAgent: String
    @State private var autofillUsername: String
    @State private var autofillPassword: String
    @State private var color: ProfileColor
    @State private var localError: PresentedError?

    init(
        profile: BrowserProfile?,
        onSave: @escaping (ProfileEditorSubmission) throws -> Void
    ) {
        self.originalProfile = profile
        self.onSave = onSave
        _name = State(initialValue: profile?.name ?? "")
        _groupName = State(initialValue: profile?.groupName ?? "")
        _homePageText = State(initialValue: profile?.homePage.absoluteString ?? BrowserProfile.defaultHomePage.absoluteString)
        _userAgent = State(initialValue: profile?.userAgent ?? BrowserProfile.defaultUserAgent)
        _autofillUsername = State(initialValue: "")
        _autofillPassword = State(initialValue: "")
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

                    Button("恢复 iPhone Safari 默认值", systemImage: "arrow.counterclockwise") {
                        userAgent = BrowserProfile.defaultUserAgent
                    }
                    Button("随机生成合理 UA", systemImage: "shuffle") {
                        userAgent = BrowserProfile.randomUserAgent()
                    }
                }

                Section("自动填充") {
                    TextField("账号（可选）", text: $autofillUsername)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("密码（可选）", text: $autofillPassword)
                    Text("填写账号和密码后，会安全保存到钥匙串，并可在浏览器的凭据入口中填充。编辑已有环境时留空会保留原凭据。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(originalProfile == nil ? "新建环境" : "编辑环境")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Text("取消")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        save()
                    } label: {
                        Text("完成")
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
                    autofillUsername: autofillUsername,
                    autofillPassword: autofillPassword
                ))
            }
            dismiss()
        } catch {
            localError = PresentedError(message: error.localizedDescription)
        }
    }
}

enum ProfileEditorSubmission {
    case create(
        name: String,
        groupName: String,
        homePage: URL,
        userAgent: String,
        color: ProfileColor,
        autofillUsername: String,
        autofillPassword: String
    )
    case update(BrowserProfile, autofillUsername: String, autofillPassword: String)
}
