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
                    TextField("分组名称", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()

                    TextField("代号（可选）", text: $code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Emoji（可选）", text: $emoji)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if !emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("清除 Emoji", systemImage: "xmark.circle") {
                            emoji = ""
                        }
                        .foregroundStyle(.secondary)
                    }
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
                            .buttonStyle(.plain)
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

    private var previewEmoji: String {
        normalizedEmoji ?? "📁"
    }

    @ViewBuilder
    private var groupPreview: some View {
        HStack(spacing: 12) {
            Text(previewEmoji)
                .font(.title)
                .frame(width: 48, height: 48)
                .background(group.color.color.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(normalizedName.isEmpty ? "分组名称" : normalizedName)
                        .font(.headline)
                        .foregroundStyle(normalizedName.isEmpty ? Color.secondary : Color.primary)
                        .lineLimit(1)

                    if let normalizedCode {
                        Text(normalizedCode)
                            .font(.caption.monospaced().weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Text("\(group.profiles.count) 个环境")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(previewEmoji)，\(normalizedName.isEmpty ? "分组名称" : normalizedName)")
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
