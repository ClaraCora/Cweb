import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct BackupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var exportPassword = ""
    @State private var confirmPassword = ""
    @State private var importPassword = ""
    @State private var backupDocument: BackupDocument?
    @State private var showsExporter = false
    @State private var showsImporter = false
    @State private var pendingImport: BackupImportFile?
    @State private var isReadingBackup = false
    @State private var importErrorMessage: String?
    @State private var presentedError: PresentedError?
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("导出") {
                    SecureField("备份密码（至少 8 个字符）", text: $exportPassword)
                    SecureField("再次输入密码", text: $confirmPassword)
                    Button("导出加密备份", systemImage: "lock.doc") {
                        exportBackup()
                    }
                    .disabled(
                        !model.isProfileStoreAvailable
                            || exportPassword.count < 8
                            || exportPassword != confirmPassword
                            || isReadingBackup
                    )
                }

                Section("导入") {
                    Button(pendingImport == nil ? "选择备份文件" : "重新选择备份文件", systemImage: "doc.badge.arrow.up") {
                        clearPendingImport()
                        showsImporter = true
                    }
                    .disabled(!model.isProfileStoreAvailable || isReadingBackup)

                    if isReadingBackup {
                        ProgressView("正在读取备份…")
                    }

                    if let pendingImport {
                        LabeledContent("已选文件") {
                            Text(pendingImport.filename)
                                .multilineTextAlignment(.trailing)
                                .textSelection(.enabled)
                        }
                        SecureField("备份密码（至少 8 个字符）", text: $importPassword)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: importPassword) { _, _ in
                                importErrorMessage = nil
                            }
                        Button("解锁并导入", systemImage: "lock.open") {
                            importBackup()
                        }
                        .disabled(!model.isProfileStoreAvailable || importPassword.count < 8)
                        Button("取消导入", role: .cancel) {
                            clearPendingImport()
                        }
                    }

                    if let importErrorMessage {
                        Label(importErrorMessage, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                    Text("导入会新增环境，不会覆盖已有环境。网站 Cookie 和缓存不在备份中。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("加密备份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        clearPendingImport()
                        dismiss()
                    }
                    .disabled(isReadingBackup)
                }
            }
            .fileExporter(
                isPresented: $showsExporter,
                document: backupDocument,
                contentType: .json,
                defaultFilename: BackupDocument.defaultFilename
            ) { result in
                if case .failure(let error) = result {
                    presentedError = PresentedError(message: error.localizedDescription)
                }
            }
            .sheet(isPresented: $showsImporter) {
                BackupFilePicker { url in
                    showsImporter = false
                    if let url {
                        selectBackup(from: url)
                    }
                }
                .ignoresSafeArea()
            }
            .alert(item: $presentedError) { error in
                Alert(title: Text("备份失败"), message: Text(error.message), dismissButton: .default(Text("好")))
            }
            .alert("导入完成", isPresented: statusAlertBinding) {
                Button("好", role: .cancel) {}
            } message: {
                Text(statusMessage ?? "")
            }
        }
        .interactiveDismissDisabled(isReadingBackup)
    }

    private func selectBackup(from url: URL) {
        clearPendingImport()
        isReadingBackup = true
        Task {
            defer { isReadingBackup = false }
            do {
                pendingImport = try await Task.detached(priority: .userInitiated) {
                    try BackupImportFile(contentsOf: url)
                }.value
            } catch {
                importErrorMessage = error.localizedDescription
            }
        }
    }

    private func clearPendingImport() {
        pendingImport = nil
        importPassword = ""
        importErrorMessage = nil
    }

    private func exportBackup() {
        guard model.isProfileStoreAvailable else {
            presentedError = PresentedError(message: ProfileError.profileStoreUnavailable.localizedDescription)
            return
        }
        do {
            backupDocument = BackupDocument(data: try BackupService(vault: model.credentialVault).export(profiles: model.profiles, password: exportPassword))
            showsExporter = true
        } catch {
            presentedError = PresentedError(message: error.localizedDescription)
        }
    }

    private func importBackup() {
        guard let pendingImport else { return }
        guard model.isProfileStoreAvailable else {
            importErrorMessage = ProfileError.profileStoreUnavailable.localizedDescription
            return
        }
        do {
            let profiles = try BackupService(vault: model.credentialVault).importProfiles(from: pendingImport.data, password: importPassword)
            try model.addImportedProfiles(profiles)
            clearPendingImport()
            statusMessage = "已新增 \(profiles.count) 个环境。"
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

    private var statusAlertBinding: Binding<Bool> {
        Binding(get: { statusMessage != nil }, set: { if !$0 { statusMessage = nil } })
    }
}
