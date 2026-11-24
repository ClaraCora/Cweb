import SwiftUI

/// The single entry point for SOCKS and app-level preferences.
@MainActor
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppSettings.appearanceModeKey) private var appearanceModeRaw = AppSettings.defaultAppearanceMode
    @State private var showsBackup = false
    private let identity = BuildIdentity()

    private var appearanceMode: Binding<AppAppearanceMode> {
        Binding(
            get: { AppAppearanceMode(rawValue: appearanceModeRaw) ?? .system },
            set: { appearanceModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                appIdentity

                VStack(alignment: .leading, spacing: 10) {
                    sectionHeading("外观", detail: "配色模式")
                    HStack(spacing: 10) {
                        ForEach(AppAppearanceMode.allCases) { mode in
                            SettingsAppearanceOption(mode: mode, isSelected: appearanceMode.wrappedValue == mode) {
                                appearanceMode.wrappedValue = mode
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    sectionHeading("浏览与自动化")
                    VStack(spacing: 0) {
                        NavigationLink {
                            SocksProxySettingsView(settings: model.socksProxyValidationSettings)
                        } label: {
                            AppSettingsRow("测速与保留规则", detail: proxyPolicySummary, icon: "slider.horizontal.3", tint: .blue)
                        }
                        .accessibilityIdentifier("settings.proxyPolicy")

                        rowDivider

                        NavigationLink {
                            GlobalScriptSettingsView()
                        } label: {
                            AppSettingsRow(
                                "签到脚本",
                                detail: model.globalScriptSettings.enabled ? "进入环境时自动运行" : "手动启动分组签到",
                                icon: "terminal",
                                tint: .indigo,
                                status: model.globalScriptSettings.enabled ? "自动" : "手动"
                            )
                        }
                        .accessibilityIdentifier("settings.script")

                        rowDivider

                        NavigationLink {
                            GroupRunHistoryView()
                        } label: {
                            AppSettingsRow("签到记录", detail: "查看分组任务结果", icon: "clock.arrow.circlepath", tint: .orange, status: "\(model.groupRunHistory.count) 条")
                        }
                        .accessibilityIdentifier("settings.history")
                    }
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                }

                Button {
                    showsBackup = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield.fill")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 36, height: 36)
                            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("加密备份")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("安全导出，随时恢复")
                                .font(.footnote)
                                .foregroundStyle(AppUI.secondaryText)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.body.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("加密备份")
                .accessibilityHint("导出加密备份或导入已有备份")
                .accessibilityIdentifier("settings.backup")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background { WorkspaceBackdrop() }
        .accessibilityIdentifier("settings.scroll")
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsBackup) {
            BackupView()
        }
    }

    private var appIdentity: some View {
        NavigationLink {
            AboutSettingsView()
        } label: {
            HStack(spacing: 12) {
                Image("SettingsAppIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("环境浏览器")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Cweb · 版本 \(identity.version)")
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(AppUI.secondaryText)
                }
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    Text("关于")
                        .font(.subheadline)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(AppUI.secondaryText)
                .accessibilityHidden(true)
            }
            .padding(16)
            .beamPanel(cornerRadius: 18, active: true)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("关于环境浏览器，版本 \(identity.version)")
        .accessibilityIdentifier("settings.about")
    }

    private func sectionHeading(_ title: String, detail: String? = nil) -> some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppUI.secondaryText)
            }
        }
        .padding(.horizontal, 2)
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 64).padding(.trailing, 16)
    }

    private var proxyPolicySummary: String {
        let settings = model.socksProxyValidationSettings
        let count = settings.maxRetainedCount == 0
            ? "数量不限"
            : "保留 \(settings.maxRetainedCount) 个"
        let order = settings.sortMode == .latencyAscending ? "延迟优先" : "导入顺序"
        return "\(order) · \(count)"
    }

}

private struct SettingsAppearanceOption: View {
    let mode: AppAppearanceMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    SettingsAppearancePreview(dark: mode == .dark)
                    if mode == .system {
                        SettingsAppearancePreview(dark: true)
                            .mask {
                                GeometryReader { geometry in
                                    Rectangle()
                                        .frame(width: geometry.size.width / 2)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                }
                            }
                    }
                }
                .frame(height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isSelected ? Color.accentColor : Color(.separator).opacity(0.35), lineWidth: isSelected ? 2 : 0.5)
                }

                HStack(spacing: 5) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color(.tertiaryLabel))
                    Text(mode.title)
                        .foregroundStyle(isSelected ? Color.accentColor : .primary)
                }
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(mode.title)
        .accessibilityValue(isSelected ? "已选择" : "未选择")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("settings.appearance." + mode.rawValue)
    }
}

/// A small, fixed-color browser preview so each choice shows its actual theme.
private struct SettingsAppearancePreview: View {
    let dark: Bool

    private var surface: Color { Color(white: dark ? 0.19 : 1) }
    private var ink: Color { Color(white: dark ? 0.58 : 0.70) }

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 3) {
                Circle().fill(Color.blue).frame(width: 4, height: 4)
                Capsule().fill(ink).frame(width: 23, height: 3)
                Spacer()
                Capsule().fill(ink.opacity(0.5)).frame(width: 10, height: 3)
            }
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.blue.opacity(dark ? 0.5 : 0.18))
                    .frame(width: 16, height: 16)
                VStack(alignment: .leading, spacing: 4) {
                    Capsule().fill(ink).frame(width: 28, height: 3)
                    Capsule().fill(ink.opacity(0.4)).frame(width: 19, height: 3)
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .background(surface, in: RoundedRectangle(cornerRadius: 6))
            HStack(spacing: 4) {
                Capsule().fill(Color.blue.opacity(0.7)).frame(width: 15, height: 3)
                Capsule().fill(ink.opacity(0.4)).frame(height: 3)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: dark ? 0.09 : 0.95))
        .accessibilityHidden(true)
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
