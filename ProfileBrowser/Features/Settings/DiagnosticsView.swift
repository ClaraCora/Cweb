import SwiftUI

@MainActor
struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss

    let session: BrowserSession

    @State private var cookieCount: Int?
    @State private var showsIPDetection = false
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
                    LabeledContent("当前路径", value: networkPathDescription)
                    Button("检测环境 IP", systemImage: "network") {
                        showsIPDetection = true
                    }
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
            .sheet(isPresented: $showsIPDetection) {
                IPDetectionView(profile: session.profile, socksProxy: session.socksProxy)
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
        Network Path: \(networkPathDescription)
        User-Agent: \(session.profile.userAgent)
        """
    }

    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.suffix(8)).uppercased()
    }

    private func refreshCookieCount() async {
        cookieCount = await session.dataStore.httpCookieStore.allCookies().count
    }

    private var networkPathDescription: String {
        if let number = session.profile.socksProxyNumber {
            guard let proxy = session.socksProxy else {
                return "第 \(number) 号代理（缺失）"
            }
            return "第 \(number) 号 · \(proxy.displayCode ?? proxy.displayAddress)"
        }
        return "设备网络"
    }
}
