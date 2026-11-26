import SwiftUI

/// Form used to edit the metadata shown for a profile group.
///
/// The view deliberately owns no persistence.  Callers provide `onSave`,
/// which can update the model and throw a domain error when the name is
/// invalid or already in use.
@MainActor
struct ProfileGroupEditorView: View {
    @Environment(\.dismiss) private var dismiss

    private let group: ProfileGroup
    private let onSave: (String, String?, String?) throws -> Void

    @State private var name: String
    @State private var code: String
    @State private var emoji: String
    @State private var presentedError: PresentedError?

    /// Creates an editor for an existing group projection.
    init(
        group: ProfileGroup,
        onSave: @escaping (_ name: String, _ code: String?, _ emoji: String?) throws -> Void
    ) {
        self.group = group
        self.onSave = onSave
        _name = State(initialValue: group.name)
        _code = State(initialValue: group.code ?? "")
        _emoji = State(initialValue: group.emoji ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    groupPreview
                } header: {
                    Text("预览")
                }

                Section("分组信息") {
                    FormField("分组名称") {
                        TextField("分组名称", text: $name)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                    }

                    FormField("代号") {
                        TextField("可选", text: $code)
                            .accessibilityLabel("代号")
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    FormField("Emoji 图标") {
                        TextField("可选", text: $emoji)
                            .accessibilityLabel("Emoji 图标")
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    if !emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("清除 Emoji", systemImage: "xmark.circle") {
                            emoji = ""
                        }
                        .foregroundStyle(AppUI.secondaryText)
                    }
                }

                Section {
                    Text("修改分组名称会同步组内环境的所属分组。以旧分组名称开头的环境名会保留后缀并自动更新；手动命名的环境不会被覆盖。")
                        .font(.footnote)
                        .foregroundStyle(AppUI.secondaryText)
                }

                Section {
                    LazyVGrid(
                        columns: [
                            GridItem(.adaptive(minimum: 48), spacing: 8)
                        ],
                        spacing: 8
                    ) {
                        ForEach(Self.commonEmojis, id: \.self) { value in
                            Button {
                                emoji = value
                            } label: {
                                Text(value)
                                    .font(.title2)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .background(
                                        emoji == value
                                            ? Color.accentColor.opacity(0.14)
                                            : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    )
                            }
                            .buttonStyle(WorkspaceRowButtonStyle())
                            .accessibilityLabel("选择 \(value) 图标")
                            .accessibilityAddTraits(emoji == value ? .isSelected : [])
                        }
                    }
                    .frame(maxWidth: .infinity)
                } header: {
                    Text("常用图标")
                } footer: {
                    Text("也可以直接输入任意 Emoji。")
                }
            }
            .navigationTitle("编辑分组")
            .navigationBarTitleDisplayMode(.inline)
            .editorDismissProtection(isModified: hasChanges)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        save()
                    }
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

    private var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasChanges: Bool {
        name != group.name || code != (group.code ?? "") || emoji != (group.emoji ?? "")
    }

    private var normalizedCode: String? {
        let value = code.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private var normalizedEmoji: String? {
        let value = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : String(value.prefix(4))
    }

    private var isValid: Bool {
        !normalizedName.isEmpty
    }

    private var groupPreview: some View {
        HStack(spacing: AppUI.Spacing.row) {
            ProfileGroupIcon(emoji: normalizedEmoji)
            VStack(alignment: .leading, spacing: AppUI.Spacing.tight) {
                Text(normalizedName.isEmpty ? "分组名称" : normalizedName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(normalizedName.isEmpty ? AppUI.secondaryText : Color.primary)
                    .lineLimit(2)
                if let normalizedCode {
                    Text(normalizedCode)
                        .font(.footnote.monospaced())
                        .foregroundStyle(AppUI.secondaryText)
                        .lineLimit(1)
                }
                Text("\(group.profiles.count) 个环境")
                    .font(.footnote)
                    .foregroundStyle(AppUI.secondaryText)
            }
        }
        .padding(.vertical, AppUI.Spacing.tight)
        .accessibilityElement(children: .combine)
    }

    private func save() {
        guard isValid else {
            presentedError = PresentedError(message: "分组名称不能为空。")
            return
        }

        do {
            try onSave(normalizedName, normalizedCode, normalizedEmoji)
            dismiss()
        } catch {
            presentedError = PresentedError(message: error.localizedDescription)
        }
    }

    private static let commonEmojis = [
        "📁", "⭐️", "💼", "🏠", "🛒", "💰", "🎮", "📚", "✈️", "🔒", "🧪", "🌐"
    ]
}
