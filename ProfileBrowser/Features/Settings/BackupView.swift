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
    @State private var showsImportPassword = false
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
                    .disabled(exportPassword.count < 8 || exportPassword != confirmPassword)
                }

                Section("导入") {
                    Button("选择备份文件", systemImage: "doc.badge.arrow.up") {
                        showsImporter = true
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
                    Button("完成") { dismiss() }
                }
            }
            .fileExporter(
                isPresented: $showsExporter,
                document: backupDocument,
                contentType: .data,
                defaultFilename: "ProfileBrowser-backup"
            ) { result in
                if case .failure(let error) = result {
                    presentedError = PresentedError(message: error.localizedDescription)
                }
            }
            .fileImporter(
                isPresented: $showsImporter,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    importPassword = ""
                    pendingImportURL = url
                    showsImportPassword = true
                case .failure(let error):
                    presentedError = PresentedError(message: error.localizedDescription)
                }
            }
            .sheet(isPresented: $showsImportPassword) {
                NavigationStack {
                    Form {
                        SecureField("备份密码", text: $importPassword)
                    }
                    .navigationTitle("解锁备份")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") { showsImportPassword = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("导入") { importBackup() }
                                .disabled(importPassword.isEmpty)
                        }
                    }
                }
                .presentationDetents([.height(220)])
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
    }

    @State private var pendingImportURL: URL?

    private func exportBackup() {
        do {
            backupDocument = BackupDocument(data: try BackupService(vault: model.credentialVault).export(profiles: model.profiles, password: exportPassword))
            showsExporter = true
        } catch {
            presentedError = PresentedError(message: error.localizedDescription)
        }
    }

    private func importBackup() {
        guard let url = pendingImportURL else { return }
        do {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let profiles = try BackupService(vault: model.credentialVault).importProfiles(from: Data(contentsOf: url), password: importPassword)
            for profile in profiles {
                try model.addImportedProfile(profile)
            }
            showsImportPassword = false
            statusMessage = "已新增 \(profiles.count) 个环境。"
        } catch {
            presentedError = PresentedError(message: error.localizedDescription)
        }
    }

    private var statusAlertBinding: Binding<Bool> {
        Binding(get: { statusMessage != nil }, set: { if !$0 { statusMessage = nil } })
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    static var writableContentTypes: [UTType] { [.data] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
