import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct SocksProxyImportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var source = 0
    @State private var urlText = ""
    @State private var text = ""
    @State private var filename: String?
    @State private var showsFilePicker = false
    @State private var task: Task<Void, Never>?
    @State private var busy = false
    @State private var report: ProxyImportReport?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    sourcePicker
                    if source == 0 {
                        FormField("订阅链接") {
                            TextField("https://example.com/proxies.txt", text: $urlText)
                                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                                .accessibilityLabel("订阅链接")
                        }
                    } else if source == 1 {
                        Button(filename ?? "选择 TXT 文件") { showsFilePicker = true }
                    } else {
                        TextEditor(text: $text).frame(minHeight: 150)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityLabel("代理文本，每行一个 SOCKS 地址")
                    }
                    Text("每行一个 SOCKS 地址，最多 2 MB。导出文件可直接重新导入。相同地址会更新凭据。")
                        .font(.footnote).foregroundStyle(AppUI.secondaryText)
                }.disabled(busy)
                if busy {
                    ProgressView("正在导入…")
                    Button("取消导入") { task?.cancel() }
                }
                if let report {
                    Section("导入结果") {
                        Text(report.summary)
                        ForEach(report.invalid) { issue in
                            Text("第 \(issue.line) 行：\(issue.reason)").font(.footnote)
                        }
                    }
                }
                if let errorMessage {
                    Section { AppStatusMessage(message: errorMessage, tone: .error) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .readableListMargins()
            .navigationTitle("导入代理").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") { importValues() }.disabled(busy || (source == 0 ? urlText.isEmpty : text.isEmpty))
                }
            }
            .fileImporter(isPresented: $showsFilePicker, allowedContentTypes: [.plainText, .data, .item]) { result in
                do {
                    let url = try result.get()
                    busy = true
                    task = Task {
                        defer { busy = false }
                        do {
                            text = try await BackupService.background { try SocksProxyImportService.readTextFile(url) }
                            filename = url.lastPathComponent
                        } catch is CancellationError { }
                        catch { errorMessage = error.localizedDescription }
                    }
                } catch { errorMessage = error.localizedDescription }
            }
        }
        .interactiveDismissDisabled(busy)
        .onDisappear { task?.cancel(); text = "" }
    }

    @ViewBuilder
    private var sourcePicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            sourceOptions.pickerStyle(.menu)
        } else {
            sourceOptions.pickerStyle(.segmented)
        }
    }

    private var sourceOptions: some View {
        Picker("来源", selection: $source) {
            Text("链接").tag(0)
            Text("TXT 文件").tag(1)
            Text("粘贴文本").tag(2)
        }
    }

    private func importValues() {
        busy = true; report = nil; errorMessage = nil
        task = Task {
            defer { busy = false }
            do {
                if source == 0 {
                    guard let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw SocksProxyImportError.invalidFeedURL }
                    report = try await model.importSocksProxies(from: url)
                } else { report = try model.importSocksProxies(text: text) }
            } catch is CancellationError { }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
