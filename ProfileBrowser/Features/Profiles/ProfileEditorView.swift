import SwiftUI

@MainActor
struct ProfileEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private let originalProfile: BrowserProfile?
    private let initialGroupName: String
    private let onSave: (ProfileEditorSubmission) throws -> Void

    @State private var name: String
    @State private var groupName: String
    @State private var homePageText: String
    @State private var userAgent: String
    @State private var selectedUserAgentName: String
    @State private var generatedUserAgentsByGroup: [String: Set<String>] = [:]
    @State private var autofillUsername: String
    @State private var autofillPassword: String
    @State private var socksProxyNumber: Int?
    @State private var color: ProfileColor
    @State private var localError: PresentedError?
    @State private var showsGroupSelection = false
    @State private var showsProxySelection = false
    @State private var showsUserAgentEditor = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case name, homePage, username, password, userAgent }

    init(
        profile: BrowserProfile?,
        defaultGroupName: String? = nil,
        onSave: @escaping (ProfileEditorSubmission) throws -> Void
    ) {
        self.originalProfile = profile
        self.initialGroupName = profile?.groupName ?? defaultGroupName ?? ""
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
                basicSection
                proxySection
                autofillSection
                userAgentSection
                colorSection
            }
            .navigationTitle(originalProfile == nil ? "新建环境" : "编辑环境")
            .navigationBarTitleDisplayMode(.inline)
            .editorDismissProtection(isModified: hasChanges)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        save()
                    }
                    .disabled(!isValid)
                    .accessibilityIdentifier("editor.save")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘", systemImage: "keyboard.chevron.compact.down") {
                        focusedField = nil
                    }
                }
            }
            .sheet(isPresented: $showsGroupSelection) {
                ProfileGroupSelectionView(selection: $groupName)
            }
            .sheet(isPresented: $showsProxySelection) {
                ProfileProxySelectionView(
                    selection: $socksProxyNumber,
                    groupName: normalizedGroupName,
                    profileID: originalProfile?.id
                )
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

    private var basicSection: some View {
        Section("基本信息") {
            FormField("环境名称") {
                TextField("环境名称", text: $name)
                    .textInputAutocapitalization(.words)
                    .focused($focusedField, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .homePage }
                    .accessibilityIdentifier("profileEditor.name")
            }
            Button {
                focusedField = nil
                showsGroupSelection = true
            } label: {
                LabeledContent("分组", value: currentDisplayGroupName)
            }
            .accessibilityIdentifier("profileEditor.group")
            FormField("主页网址") {
                TextField("https://example.com", text: $homePageText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .homePage)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
                    .accessibilityIdentifier("profileEditor.homePage")
                if validatedHomePage == nil {
                    InlineValidationMessage(message: "请输入完整的 HTTP 或 HTTPS 网址。")
                }
            }
        }
    }

    private var proxySection: some View {
        Section {
            Button {
                focusedField = nil
                showsProxySelection = true
            } label: {
                LabeledContent("代理编号", value: socksProxyNumber.map { "第 \($0) 号" } ?? "不使用代理")
            }
            .accessibilityIdentifier("profileEditor.proxy")

            if let socksProxyNumber {
                if let occupant = proxyOccupant(for: socksProxyNumber) {
                    InlineValidationMessage(message: "第 \(socksProxyNumber) 号已由“\(occupant.name)”使用，请选择其他编号。")
                }
                if let proxy = model.socksProxy(forDisplayNumber: socksProxyNumber) {
                    if let code = proxy.displayCode { LabeledContent("代号", value: code) }
                    LabeledContent("地址", value: proxy.displayAddress)
                        .font(.subheadline)
                } else {
                    InlineValidationMessage(message: "第 \(socksProxyNumber) 号当前缺失，补充代理后才能进入环境。")
                }
            }
        } header: {
            Text("SOCKS 代理")
        } footer: {
            Text("绑定显示编号，同组不重复。重新排序后，同一编号会使用新的代理内容。")
        }
    }

    private var autofillSection: some View {
        Section {
            FormField("账号") {
                TextField("可选", text: $autofillUsername)
                    .textContentType(nil)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .username)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
            }
            FormField("密码") {
                TextField("可选", text: $autofillPassword)
                    .textContentType(nil)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .password)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
            }
            if !autofillFieldsValid {
                InlineValidationMessage(message: "账号和密码需要同时填写，或同时留空。")
            }
        } header: {
            Text("自动填充")
        } footer: {
            Text(originalProfile == nil ? "账号密码仅在本 App 内管理与填充。" : "留空会保留已保存的账号密码；填写后更新当前站点的账号。")
        }
    }

    private var userAgentSection: some View {
        Section {
            Picker("浏览器", selection: $selectedUserAgentName) {
                ForEach(BrowserProfile.userAgentPresets) { preset in
                    Text(preset.name).tag(preset.name)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("ua.browser")
            .onChange(of: selectedUserAgentName) { _, newValue in
                if let preset = BrowserProfile.userAgentPresets.first(where: { $0.name == newValue }) {
                    userAgent = preset.value
                }
            }

            if let details = BrowserProfile.userAgentDetails(for: userAgent) {
                Text(details.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("随机参数", systemImage: "shuffle", action: randomizeUserAgent)
                .accessibilityIdentifier("ua.randomize")
            DisclosureGroup("查看与编辑完整 UA", isExpanded: $showsUserAgentEditor) {
                TextField("User-Agent", text: $userAgent, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(3...10)
                    .font(.subheadline.monospaced())
                    .focused($focusedField, equals: .userAgent)
                    .accessibilityIdentifier("ua.value")
                Button("恢复 Safari 默认值", systemImage: "arrow.counterclockwise") {
                    selectedUserAgentName = "iPhone Safari"
                    userAgent = BrowserProfile.defaultUserAgent
                }
                .accessibilityIdentifier("ua.restore")
            }
        } header: {
            Text("User-Agent")
        } footer: {
            Text("只改变浏览器声明，不改变真实设备和 WebKit 参数。")
        }
    }

    private var colorSection: some View {
        Section("标识颜色") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                ForEach(ProfileColor.allCases) { option in
                    Button { color = option } label: {
                        ZStack {
                            Circle().fill(option.color).frame(width: 28, height: 28)
                            if color == option {
                                Circle().strokeBorder(Color.primary, lineWidth: 2).frame(width: 38, height: 38)
                            }
                        }
                        .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.title)
                    .accessibilityValue(color == option ? "已选择" : "未选择")
                    .accessibilityAddTraits(color == option ? .isSelected : [])
                }
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

    private var hasChanges: Bool {
        name != (originalProfile?.name ?? "")
            || groupName != initialGroupName
            || homePageText != (originalProfile?.homePage.absoluteString ?? BrowserProfile.defaultHomePage.absoluteString)
            || userAgent != (originalProfile?.userAgent ?? BrowserProfile.defaultUserAgent)
            || color != (originalProfile?.color ?? .indigo)
            || socksProxyNumber != originalProfile?.socksProxyNumber
            || !autofillUsername.isEmpty || !autofillPassword.isEmpty
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !userAgent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && validatedHomePage != nil
            && autofillFieldsValid
            && (socksProxyNumber.map { !isProxyNumberOccupied($0) } ?? true)
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

    private func proxyOccupant(for number: Int) -> BrowserProfile? {
        model.profileUsingSocksProxyNumber(
            number,
            inGroupNamed: normalizedGroupName,
            excludingProfileID: originalProfile?.id
        )
    }

    private func isProxyNumberOccupied(_ number: Int) -> Bool {
        proxyOccupant(for: number) != nil
    }

    private func randomizeUserAgent() {
        let groupName = currentDisplayGroupName
        var excludedValues = Set(
            model.profiles.lazy
                .filter {
                    $0.id != originalProfile?.id
                        && $0.displayGroupName == groupName
                }
                .map(\.userAgent)
        )
        excludedValues.formUnion(generatedUserAgentsByGroup[groupName, default: []])
        excludedValues.insert(userAgent)

        guard let value = BrowserProfile.uniqueRandomUserAgent(
            for: selectedUserAgentName,
            excluding: excludedValues
        ) else {
            localError = PresentedError(
                message: "当前浏览器的可用 UA 组合已全部使用，请选择其他浏览器或手动填写。"
            )
            return
        }

        userAgent = value
        generatedUserAgentsByGroup[groupName, default: []].insert(value)
    }

    private var currentDisplayGroupName: String {
        normalizedGroupName ?? "未分组"
    }

    private var normalizedGroupName: String? {
        let value = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
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
