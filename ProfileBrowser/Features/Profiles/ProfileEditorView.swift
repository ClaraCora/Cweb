import SwiftUI

@MainActor
struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss

    private let originalProfile: BrowserProfile?
    private let onSave: (ProfileEditorSubmission) throws -> Void

    @State private var name: String
    @State private var homePageText: String
    @State private var userAgent: String
    @State private var color: ProfileColor
    @State private var localError: PresentedError?

    init(
        profile: BrowserProfile?,
        onSave: @escaping (ProfileEditorSubmission) throws -> Void
    ) {
        self.originalProfile = profile
        self.onSave = onSave
        _name = State(initialValue: profile?.name ?? "")
        _homePageText = State(initialValue: profile?.homePage.absoluteString ?? BrowserProfile.defaultHomePage.absoluteString)
        _userAgent = State(initialValue: profile?.userAgent ?? BrowserProfile.defaultUserAgent)
        _color = State(initialValue: profile?.color ?? .indigo)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("环境名称", text: $name)
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
                }
            }
            .navigationTitle(originalProfile == nil ? "新建环境" : "编辑环境")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { save() }
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
    }

    private func save() {
        guard let homePage = validatedHomePage else {
            localError = PresentedError(message: "主页必须是有效的 HTTP 或 HTTPS 网址。")
            return
        }

        do {
            if var profile = originalProfile {
                profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                profile.homePage = homePage
                profile.userAgent = userAgent.trimmingCharacters(in: .whitespacesAndNewlines)
                profile.color = color
                try onSave(.update(profile))
            } else {
                try onSave(.create(
                    name: name,
                    homePage: homePage,
                    userAgent: userAgent,
                    color: color
                ))
            }
            dismiss()
        } catch {
            localError = PresentedError(message: error.localizedDescription)
        }
    }
}

enum ProfileEditorSubmission {
    case create(name: String, homePage: URL, userAgent: String, color: ProfileColor)
    case update(BrowserProfile)
}
