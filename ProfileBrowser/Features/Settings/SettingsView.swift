import SwiftUI

/// The single entry point for SOCKS and app-level preferences.
@MainActor
struct SettingsView: View {
    @Environment(AppModel.self) private var model
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
                    SocksProxySettingsView(settings: model.socksProxyValidationSettings)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("验证与保留规则")
                            Text(proxyPolicySummary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(.tint)
                    }
                }
            } header: {
                Text("代理策略")
            } footer: {
                Text("代理节点、导入和测试位于“代理”页。验证只会在你主动执行时联网。")
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
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showsBackup) {
            BackupView()
        }
    }

    private var proxyPolicySummary: String {
        let settings = model.socksProxyValidationSettings
        let count = settings.maxRetainedCount == 0
            ? "不限保留数量"
            : "最多保留 \(settings.maxRetainedCount) 个"
        return "\(settings.sortMode.title) · \(count)"
    }
}
