import SwiftUI

/// Imports a plain-text feed from one HTTP(S) URL. Keeping the URL entry in a
/// sheet makes network access explicit and avoids any background requests.
@MainActor
struct SocksProxyImportView: View {
    @Environment(\.dismiss) private var dismiss

    private let initialURL: URL?
    private let onImport: (URL) async throws -> Void

    @State private var urlText: String
    @State private var isImporting = false
    @State private var presentedError: PresentedError?

    init(
        url: URL? = nil,
        onImport: @escaping (URL) async throws -> Void
    ) {
        initialURL = url
        self.onImport = onImport
        _urlText = State(initialValue: url?.absoluteString ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("订阅链接") {
                    TextField("https://example.com/proxies.txt", text: $urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Text("链接应返回每行一个 SOCKS 地址的纯文本。只有你主动点击导入时才会访问网络。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(initialURL == nil ? "导入代理" : "拉取预设")
            .navigationBarTitleDisplayMode(.inline)
            .editorDismissProtection(
                isModified: urlText != (initialURL?.absoluteString ?? ""),
                isBusy: isImporting
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") {
                        importFeed()
                    }
                    .disabled(!isValidURL || isImporting)
                }
            }
            .overlay {
                if isImporting {
                    ProgressView("正在拉取")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .alert(item: $presentedError) { error in
                Alert(
                    title: Text("导入失败"),
                    message: Text(error.message),
                    dismissButton: .default(Text("好"))
                )
            }
        }
    }

    private var validatedURL: URL? {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil else { return nil }
        return url
    }

    private var isValidURL: Bool { validatedURL != nil }

    private func importFeed() {
        guard let url = validatedURL else {
            presentedError = PresentedError(message: "请输入有效的 HTTP 或 HTTPS 订阅链接。")
            return
        }

        isImporting = true
        Task { @MainActor in
            defer { isImporting = false }
            do {
                try await onImport(url)
                dismiss()
            } catch {
                presentedError = PresentedError(message: error.localizedDescription)
            }
        }
    }
}
