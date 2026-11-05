import LocalAuthentication
import SwiftUI

@MainActor
struct CredentialListView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var authenticationToken = UUID()
    @Environment(\.dismiss) private var dismiss

    let profile: BrowserProfile
    let origin: WebOrigin
    let vault: CredentialVault
    let onFill: (StoredCredential) async throws -> CredentialFillResult

    @State private var authenticationState: AuthenticationState = .locked
    @State private var credentials: [StoredCredential] = []
    @State private var editorMode: CredentialEditorMode?
    @State private var presentedError: PresentedError?
    @State private var statusMessage: String?
    @State private var credentialBeingDeleted: StoredCredential?

    var body: some View {
        NavigationStack {
            Group {
                switch authenticationState {
                case .locked:
                    ContentUnavailableView {
                        Label("凭据已锁定", systemImage: "lock.fill")
                    } actions: {
                        Button("解锁", systemImage: "faceid") {
                            Task { await unlock() }
                        }
                        .buttonStyle(.borderedProminent)
                    }

                case .unlocking:
                    ProgressView("正在验证")

                case .unlocked:
                    credentialContent
                }
            }
            .navigationTitle(origin.host)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                if authenticationState == .unlocked {
                    ToolbarItem(placement: .primaryAction) {
                        Button("添加凭据", systemImage: "plus") {
                            editorMode = .create
                        }
                    }
                }
            }
            .sheet(item: $editorMode) { mode in
                CredentialEditorView(
                    profileID: profile.id,
                    origin: origin,
                    credential: mode.credential
                ) { credential in
                    try vault.save(credential)
                    try reloadCredentials()
                }
            }
            .alert("删除凭据？", isPresented: deletionAlertBinding, presenting: credentialBeingDeleted) { credential in
                Button("删除", role: .destructive) {
                    delete(credential)
                }
                Button("取消", role: .cancel) {}
            } message: { credential in
                Text("将删除“\(credential.label.isEmpty ? credential.username : credential.label)”。")
            }
            .alert(item: $presentedError) { error in
                Alert(
                    title: Text("凭据操作失败"),
                    message: Text(error.message),
                    dismissButton: .default(Text("好"))
                )
            }
            .alert("填充结果", isPresented: statusAlertBinding) {
                Button("好", role: .cancel) {}
            } message: {
                Text(statusMessage ?? "")
            }
            .task { await unlock() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    authenticationToken = UUID()
                    authenticationState = .locked
                    credentials = []
                    editorMode = nil
                    credentialBeingDeleted = nil
                }
            }
        }
    }

    @ViewBuilder
    private var credentialContent: some View {
        if credentials.isEmpty {
            ContentUnavailableView {
                Label("没有保存的凭据", systemImage: "key")
            } actions: {
                Button("添加凭据", systemImage: "plus") {
                    editorMode = .create
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            List {
                Section {
                    Text("点击账号后，由当前网页脚本直接填入登录表单，不调用 iOS 系统自动填充。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    ForEach(credentials) { credential in
                        Button {
                            fill(credential)
                        } label: {
                            CredentialRow(credential: credential)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("删除", systemImage: "trash", role: .destructive) {
                                credentialBeingDeleted = credential
                            }
                            Button("编辑", systemImage: "pencil") {
                                editorMode = .edit(credential)
                            }
                            .tint(.indigo)
                        }
                    }
                } header: {
                    Text("\(credentials.count) 个账号")
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var deletionAlertBinding: Binding<Bool> {
        Binding(
            get: { credentialBeingDeleted != nil },
            set: { if !$0 { credentialBeingDeleted = nil } }
        )
    }

    private var statusAlertBinding: Binding<Bool> {
        Binding(
            get: { statusMessage != nil },
            set: { if !$0 { statusMessage = nil } }
        )
    }

    private func unlock() async {
        guard authenticationState != .unlocking else { return }
        let token = UUID()
        authenticationToken = token
        authenticationState = .unlocking

        do {
            try await AuthenticationService().authenticate(reason: "查看并填充“\(profile.name)”保存的账号密码")
            guard authenticationToken == token, scenePhase != .background else { return }
            try reloadCredentials()
            authenticationState = .unlocked
        } catch {
            guard authenticationToken == token else { return }
            authenticationState = .locked
            if let laError = error as? LAError, laError.code == .userCancel || laError.code == .appCancel {
                return
            }
            presentedError = PresentedError(message: error.localizedDescription)
        }
    }

    private func reloadCredentials() throws {
        credentials = try vault.credentials(profileID: profile.id, origin: origin)
    }

    private func fill(_ credential: StoredCredential) {
        guard authenticationState == .unlocked, scenePhase == .active else { return }
        Task {
            do {
                let result = try await onFill(credential)
                if result.passwordFilled && result.usernameFilled {
                    dismiss()
                } else if result.passwordFilled {
                    statusMessage = "已填入密码；同一登录表单内未找到用户名输入框，请检查账号后登录。"
                } else if result.usernameFilled {
                    statusMessage = "已填入用户名，当前页面没有找到密码框。"
                } else {
                    statusMessage = "当前页面没有找到可填充的登录输入框。"
                }
            } catch {
                presentedError = PresentedError(message: error.localizedDescription)
            }
        }
    }

    private func delete(_ credential: StoredCredential) {
        do {
            try vault.delete(credential)
            try reloadCredentials()
        } catch {
            presentedError = PresentedError(message: error.localizedDescription)
        }
    }
}

@MainActor
private struct CredentialRow: View {
    let credential: StoredCredential

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.fill")
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(credential.label.isEmpty ? credential.username : credential.label)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if !credential.label.isEmpty {
                    Text(credential.username)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "arrow.up.left")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("填充账号 \(credential.username)")
    }
}

private enum AuthenticationState: Equatable {
    case locked
    case unlocking
    case unlocked
}

private enum CredentialEditorMode: Identifiable {
    case create
    case edit(StoredCredential)

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let credential): credential.id.uuidString
        }
    }

    var credential: StoredCredential? {
        switch self {
        case .create: nil
        case .edit(let credential): credential
        }
    }
}
