import SwiftUI

@MainActor
struct CredentialEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let profileID: UUID
    let origin: WebOrigin
    let originalCredential: StoredCredential?
    let onSave: (StoredCredential) throws -> Void

    @State private var label: String
    @State private var username: String
    @State private var password: String
    @State private var presentedError: PresentedError?

    init(
        profileID: UUID,
        origin: WebOrigin,
        credential: StoredCredential?,
        onSave: @escaping (StoredCredential) throws -> Void
    ) {
        self.profileID = profileID
        self.origin = origin
        self.originalCredential = credential
        self.onSave = onSave
        _label = State(initialValue: credential?.label ?? "")
        _username = State(initialValue: credential?.username ?? "")
        _password = State(initialValue: credential?.password ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("网站") {
                    LabeledContent("地址", value: origin.displayString)
                }

                Section("账号") {
                    TextField("名称（可选）", text: $label)
                    TextField("用户名或邮箱", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("密码", text: $password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle(originalCredential == nil ? "添加凭据" : "编辑凭据")
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

    private var isValid: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    private var hasChanges: Bool {
        label != (originalCredential?.label ?? "")
            || username != (originalCredential?.username ?? "")
            || password != (originalCredential?.password ?? "")
    }

    private func save() {
        let credential = StoredCredential(
            id: originalCredential?.id ?? UUID(),
            profileID: profileID,
            origin: origin,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password,
            label: label.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: originalCredential?.createdAt ?? .now,
            updatedAt: .now
        )

        do {
            try onSave(credential)
            dismiss()
        } catch {
            presentedError = PresentedError(message: error.localizedDescription)
        }
    }
}
