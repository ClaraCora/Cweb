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
                Picker(selection: appearanceMode) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                } label: {
                    AppSettingsRow("配色模式", icon: "circle.lefthalf.filled")
                }
            }

            Section("自动化与网络") {
                NavigationLink {
                    GlobalScriptSettingsView()
                } label: {
                    AppSettingsRow("签到脚本", detail: model.globalScriptSettings.enabled ? "进入环境时自动运行" : "手动启动分组签到", icon: "checkmark.circle")
                }
                NavigationLink {
                    SocksProxySettingsView(settings: model.socksProxyValidationSettings)
                } label: {
                    AppSettingsRow("测速与保留规则", detail: proxyPolicySummary, icon: "slider.horizontal.3")
                }
            }

            Section("数据") {
                NavigationLink {
                    GroupRunHistoryView()
                } label: {
                    AppSettingsRow("签到记录", icon: "clock.arrow.circlepath")
                }
                Button {
                    showsBackup = true
                } label: {
                    HStack {
                        AppSettingsRow("加密备份", icon: "lock.doc")
                        Spacer(minLength: AppUI.Spacing.related)
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.caption)
                            .foregroundStyle(AppUI.secondaryText)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityLabel("加密备份")
                .accessibilityHint("导出加密备份或导入已有备份")
                .accessibilityIdentifier("settings.backup")
            }

            Section {
                NavigationLink {
                    AboutSettingsView()
                } label: {
                    AppSettingsRow("关于环境浏览器", icon: "info.circle")
                }
            }
        }
        .formStyle(.grouped)
        .readableListMargins()
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

private struct AboutSettingsView: View {
    @Environment(AppModel.self) private var model
    private let identity = BuildIdentity()
    @State private var copied = false
    var body: some View {
        Form {
            Section {
                Label("环境浏览器 · Cweb", systemImage: "safari")
                    .font(.headline)
                LabeledContent("版本", value: identity.version)
                LabeledContent("构建", value: identity.build)
                LabeledContent("提交", value: identity.commit)
                Button(copied ? "已复制构建信息" : "复制构建信息", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = identity.description
                    copied = true
                }
                if model.websiteCleanupFailureCount > 0 {
                    Text("\(model.websiteCleanupFailureCount) 个旧网站存储清理失败，下次冷启动将重试。")
                        .font(.footnote).foregroundStyle(AppUI.secondaryText)
                }
            }
        }
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }
}
