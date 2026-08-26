import SwiftUI

@MainActor
struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss

    let session: BrowserSession

    @State private var cookieCount: Int?
    @State private var publicIPAddress: String?
    @State private var isLookingUpIP = false
    @State private var presentedError: PresentedError?

    var body: some View {
        NavigationStack {
            Form {
                Section("环境") {
                    LabeledContent("名称", value: session.profile.name)
                    LabeledContent("环境 ID", value: shortID(session.profile.id))
                    LabeledContent("存储 ID", value: shortID(session.profile.websiteDataStoreID))
                    LabeledContent("持久化", value: session.dataStore.isPersistent ? "是" : "否")
                }

                Section("当前页面") {
                    LabeledContent("站点", value: session.currentOrigin?.displayString ?? "未加载")
                    LabeledContent("Cookie") {
                        if let cookieCount {
                            Text("\(cookieCount)")
                        } else {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel("正在读取 Cookie 数量")
                        }
                    }
                    Button("刷新 Cookie 数量", systemImage: "arrow.clockwise") {
                        Task { await refreshCookieCount() }
                    }
                }

                Section("网络") {
                    if let publicIPAddress {
                        LabeledContent("公网 IP", value: publicIPAddress)
                    }
                    Button("查询当前公网 IP", systemImage: "network") {
                        Task { await lookupIPAddress() }
                    }
                    .disabled(isLookingUpIP)
                }

                Section("User-Agent") {
                    Text(session.profile.userAgent)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }

                Section {
                    ShareLink(item: diagnosticReport) {
                        Label("导出诊断报告", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .navigationTitle("诊断")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task {
                await refreshCookieCount()
            }
            .alert(item: $presentedError) { error in
                Alert(
                    title: Text("诊断失败"),
                    message: Text(error.message),
                    dismissButton: .default(Text("好"))
                )
            }
        }
    }

    private var diagnosticReport: String {
        """
        Profile Browser Diagnostics
        Environment: \(session.profile.name)
        Profile ID: \(session.profile.id.uuidString)
        Data Store ID: \(session.profile.websiteDataStoreID.uuidString)
        Persistent Store: \(session.dataStore.isPersistent ? "yes" : "no")
        Origin: \(session.currentOrigin?.displayString ?? "not loaded")
        Cookie Count: \(cookieCount.map(String.init) ?? "unknown")
        Public IP: \(publicIPAddress ?? "not queried")
        User-Agent: \(session.profile.userAgent)
        """
    }

    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.suffix(8)).uppercased()
    }

    private func refreshCookieCount() async {
        cookieCount = await session.dataStore.httpCookieStore.allCookies().count
    }

    private func lookupIPAddress() async {
        isLookingUpIP = true
        defer { isLookingUpIP = false }

        do {
            publicIPAddress = try await IPLookupService().currentIPAddress()
        } catch {
            presentedError = PresentedError(message: error.localizedDescription)
        }
    }
}
