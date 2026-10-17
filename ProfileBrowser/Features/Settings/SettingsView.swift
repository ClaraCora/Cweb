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
            Section("外观") {
                Picker("配色模式", selection: appearanceMode) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }

            Section("自动化与网络") {
                NavigationLink {
                    GlobalScriptSettingsView()
                } label: {
                    settingsRow("签到脚本", detail: model.globalScriptSettings.enabled ? "进入环境时自动运行" : "手动启动分组签到", icon: "checkmark.circle")
                }
                NavigationLink {
                    SocksProxySettingsView(settings: model.socksProxyValidationSettings)
                } label: {
                    settingsRow("测速与保留规则", detail: proxyPolicySummary, icon: "slider.horizontal.3")
                }
            }

            Section("数据") {
                Button {
                    showsBackup = true
                } label: {
                    Label("加密备份", systemImage: "lock.doc")
                }
            }

            Section {
                NavigationLink {
                    AboutSettingsView()
                } label: {
                    Label("关于环境浏览器", systemImage: "info.circle")
                }
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

    private func settingsRow(_ title: String, detail: String, icon: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon)
        }
        .padding(.vertical, 4)
    }
}

private struct AboutSettingsView: View {
    var body: some View {
        Form {
            Section {
                Label("环境浏览器 · Cweb", systemImage: "safari")
                    .font(.headline)
                LabeledContent("版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                LabeledContent("构建", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1")
            }
        }
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }
}
