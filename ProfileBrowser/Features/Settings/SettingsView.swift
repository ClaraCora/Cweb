import SwiftUI

/// The single entry point for SOCKS and app-level preferences.
@MainActor
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.appearanceModeKey) private var appearanceModeRaw = AppSettings.defaultAppearanceMode
    @State private var showsBackup = false

    private var appearanceMode: Binding<AppAppearanceMode> {
        Binding(
            get: { AppAppearanceMode(rawValue: appearanceModeRaw) ?? .system },
            set: { appearanceModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    SocksProxyListView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("SOCKS 代理")
                            Text("管理、导入和测试代理节点 · \(proxySummary)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "network")
                            .foregroundStyle(.tint)
                    }
                }

                NavigationLink {
                    SocksProxySettingsView(settings: model.socksProxyValidationSettings)
                } label: {
                    Label("SOCKS 验证设置", systemImage: "slider.horizontal.3")
                }
            } header: {
                Text("网络与代理")
            } footer: {
                Text("代理验证只会在你主动执行验证时联网。")
            }

            Section("外观") {
                Picker("配色模式", selection: appearanceMode) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }

            Section("数据") {
                Button {
                    showsBackup = true
                } label: {
                    Label("加密备份", systemImage: "lock.doc")
                }
            }

            Section("关于") {
                LabeledContent("版本") {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("构建") {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1")
                        .foregroundStyle(.secondary)
                }
                Text("环境浏览器为本地使用的多环境 WebKit 浏览器。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
            }
        }
        .sheet(isPresented: $showsBackup) {
            BackupView()
        }
    }

    private var proxySummary: String {
        let available = model.socksProxies.reduce(into: 0) { count, proxy in
            if proxy.status == .available { count += 1 }
        }
        return "\(model.socksProxies.count) 个节点，\(available) 个可用"
    }
}
