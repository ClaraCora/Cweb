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
    @State private var restorePlan: BackupRestorePlan?
    @State private var restoreSettings = false
    @State private var operation: Task<Void, Never>?
    @State private var activity: String?
    @State private var errorMessage: String?
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if !model.isBackupStoreAvailable {
                    Section {
                        Label("有数据尚未成功读取，暂不能创建或恢复备份。", systemImage: "exclamationmark.circle")
                        Button("重试读取数据") {
                            model.retryLoadingBackupStores()
                            Task { await model.retryLoadingProfiles() }
                        }.disabled(isBusy)
                    }
                }
                if let activity {
                    Section {
                        ProgressView(activity)
                        Button("取消操作", role: .cancel) { operation?.cancel() }
                    }
                }
                Section("导出") {
                    FormField("备份密码") {
                        SecureField("至少 8 个字符", text: $exportPassword)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityLabel("导出备份密码")
                    }
                    FormField("确认密码") {
                        SecureField("再次输入备份密码", text: $confirmPassword)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityLabel("确认备份密码")
                        if !confirmPassword.isEmpty, exportPassword != confirmPassword {
                            InlineValidationMessage(message: "两次输入的密码不一致。")
                        }
                    }
                    Button("导出完整加密备份", systemImage: "lock.doc") { exportBackup() }
                        .disabled(exportPassword.count < 8 || exportPassword != confirmPassword)
                    Text("包含环境、网站凭据、代理及其密码、预设链接、设置和脚本。不包含 Cookie 与缓存。")
                        .font(.footnote).foregroundStyle(AppUI.secondaryText)
                }
                .disabled(isBusy || !model.isBackupStoreAvailable)

                Section("导入") {
                    Button(pendingImport == nil ? "选择备份文件" : "重新选择备份文件", systemImage: "doc.badge.arrow.up") {
                        clearImport()
                        showsImporter = true
                    }
                    if let file = pendingImport {
                        LabeledContent("已选文件", value: file.filename)
                        if restorePlan == nil {
                            FormField("备份密码") {
                                SecureField("输入此文件的备份密码", text: $importPassword)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .accessibilityLabel("导入备份密码")
                            }
                            Button("解锁并预览", systemImage: "lock.open") { unlockBackup(file) }
                                .disabled(importPassword.count < 8)
                        }
                        Button("取消导入", role: .cancel) { clearImport() }
                    }
                    Text("支持旧版无扩展名备份，文件最大 32 MB。恢复会新增环境；同名分组会合并。")
                        .font(.footnote).foregroundStyle(AppUI.secondaryText)
                }
                .disabled(isBusy || !model.isBackupStoreAvailable)

                if let plan = restorePlan {
                    Section("恢复预览") {
                        LabeledContent("环境", value: "\(plan.profiles.count)")
                        LabeledContent("网站凭据", value: "\(plan.credentials.count)")
                        LabeledContent("新增代理", value: "\(plan.newProxyCount)")
                        LabeledContent("预设链接", value: "\(plan.archive.presets?.count ?? 0)")
                        ForEach(Array(plan.warnings.enumerated()), id: \.offset) { _, warning in
                            Text(warning).font(.footnote).foregroundStyle(AppUI.secondaryText)
                        }
                        Toggle("恢复应用设置与全局脚本", isOn: $restoreSettings)
                        Button("确认恢复", systemImage: "arrow.down.doc") { restore(plan) }
                    }
                    .disabled(isBusy)
                }
                if let errorMessage {
                    Section { AppStatusMessage(message: errorMessage, tone: .error) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .readableListMargins()
            .navigationTitle("加密备份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { clearImport(); dismiss() }.disabled(isBusy)
                }
            }
            .fileExporter(isPresented: $showsExporter, document: backupDocument, contentType: .json,
                          defaultFilename: BackupDocument.defaultFilename) { result in
                if case .failure(let error) = result { errorMessage = error.localizedDescription }
                backupDocument = nil
                exportPassword = ""
                confirmPassword = ""
            }
            .sheet(isPresented: $showsImporter) {
                BackupFilePicker { url in
                    showsImporter = false
                    if let url { readBackup(url) }
                }.ignoresSafeArea()
            }
            .alert("恢复完成", isPresented: Binding(get: { statusMessage != nil }, set: { if !$0 { statusMessage = nil } })) {
                Button("好", role: .cancel) {}
            } message: { Text(statusMessage ?? "") }
        }
        .interactiveDismissDisabled(isBusy)
        .onDisappear { operation?.cancel(); clearImport(); backupDocument = nil; exportPassword = ""; confirmPassword = "" }
    }

    private var isBusy: Bool { activity != nil }

    private func start(_ title: String, work: @escaping @MainActor () async throws -> Void) {
        guard !isBusy else { return }
        activity = title
        errorMessage = nil
        operation = Task {
            defer { activity = nil; operation = nil }
            do { try await work() }
            catch is CancellationError { }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func clearImport() {
        pendingImport = nil
        restorePlan = nil
        restoreSettings = false
        importPassword = ""
        errorMessage = nil
    }

    private func readBackup(_ url: URL) {
        clearImport()
        start("正在读取备份…") {
            let file = try await BackupService.background { try BackupImportFile(contentsOf: url) }
            try Task.checkCancellation()
            pendingImport = file
        }
    }

    private func exportBackup() {
        start("正在加密备份…") {
            let snapshot = try model.backupSnapshot()
            let password = exportPassword
            let data = try await BackupService.background { try BackupService.encrypt(snapshot, password: password) }
            try Task.checkCancellation()
            backupDocument = BackupDocument(data: data)
            showsExporter = true
        }
    }

    private func unlockBackup(_ file: BackupImportFile) {
        start("正在解锁备份…") {
            let password = importPassword
            let archive = try await BackupService.background { try BackupService.decrypt(file.data, password: password) }
            try Task.checkCancellation()
            restorePlan = model.prepareBackupRestore(archive)
            importPassword = ""
        }
    }

    private func restore(_ plan: BackupRestorePlan) {
        start("正在恢复备份…") {
            await Task.yield()
            try Task.checkCancellation()
            // The commit is synchronous so cancellation cannot split a transaction.
            statusMessage = try model.restoreBackup(plan, restoreSettings: restoreSettings)
            clearImport()
        }
    }
}
