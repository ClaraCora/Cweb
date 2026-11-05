import SwiftUI

@MainActor
struct GroupCheckInView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let controller: GroupCheckInController
    @State private var showsTaskDetails = false
    @State private var showsBrowserChrome = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let session = controller.session {
                    taskBar
                    BrowserView(
                        session: session,
                        automationSettings: controller.settings,
                        automationIsPaused: controller.isPaused,
                        browserChromePresentation: $showsBrowserChrome
                    ) { [weak run = controller] id, event in
                        run?.receive(id, event)
                    }
                        .id(session.profile.id)
                } else {
                    results
                }
            }
            .navigationTitle(controller.session?.profile.name ?? "\(controller.groupName)签到结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        controller.pause()
                        dismiss()
                    } label: {
                        if controller.session == nil {
                            Text("完成")
                        } else {
                            Label("分组", systemImage: "chevron.left")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    .accessibilityLabel(controller.session == nil ? "完成" : "返回分组")
                    .accessibilityHint(controller.session == nil ? "关闭签到结果" : "暂停当前任务并返回分组")
                }
            }
        }
        .interactiveDismissDisabled(controller.session != nil)
        .task(id: controller.session?.profile.id) {
            guard let activeSession = controller.session else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                guard controller.session === activeSession else { return }
                guard scenePhase == .active else { continue }
                await controller.recheck()
            }
        }
        .onChange(of: controller.session?.profile.id) { _, _ in
            showsBrowserChrome = false
            showsTaskDetails = false
        }
        .onDisappear { controller.pause() }
    }

    private var taskBar: some View {
        VStack(spacing: 0) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 0) {
                    taskSummary
                    taskControls.frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                HStack(spacing: 8) {
                    taskSummary
                    taskControls
                }
            }
            if showsTaskDetails { taskDetails }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var taskControls: some View {
        GroupCheckInControls(
            canStart: controller.canStart, canPause: controller.canPause, canStop: controller.canStop,
            start: controller.start, pause: controller.pause, stop: controller.stop
        )
        .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
    }

    private var taskSummary: some View {
        Button {
            showsTaskDetails.toggle()
        } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(controller.queue.index + 1)/\(controller.queue.profileIDs.count)")
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Text(statusTitle)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                }
                .lineLimit(1)
                Image(systemName: showsTaskDetails ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("本组第 \(controller.queue.index + 1) 个，共 \(controller.queue.profileIDs.count) 个，\(statusTitle)，\(currentHost)")
        .accessibilityValue(controller.session?.automationMessage ?? "")
        .accessibilityHint(showsTaskDetails ? "收起任务详情" : "展开任务详情和浏览器工具入口")
        .accessibilityIdentifier("groupCheckIn.details")
    }

    private var taskDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(controller.groupName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("已完成 \(controller.queue.completedCount) · 已跳过 \(controller.queue.skippedCount)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(controller.queue.index), total: Double(max(1, controller.queue.profileIDs.count)))
            if let message = controller.session?.automationMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
            }
            Text(controller.isPaused ? "继续后恢复自动检测。" : "每 5 秒重新检测；验证码请手动完成，确认签到后自动进入下一个。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 0) { detailActions }
            } else {
                HStack {
                    detailActions
                }
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var detailActions: some View {
        if controller.session?.automationState == .error {
            Button("重新尝试签到", systemImage: "arrow.clockwise") {
                Task { await controller.session?.resumeAutomation() }
            }
            .disabled(controller.isPaused || controller.isRefreshingBalance)
            .frame(minHeight: 44)
        }
        Button("跳过当前环境", systemImage: "forward.end") { controller.skip() }
            .disabled(!controller.canSkip)
            .frame(minHeight: 44)
            .font(.subheadline)
            .buttonStyle(.borderless)
        if !dynamicTypeSize.isAccessibilitySize { Spacer() }
        Button(showsBrowserChrome ? "收起浏览器工具" : "浏览器工具", systemImage: "safari") {
            showsBrowserChrome.toggle()
            showsTaskDetails = false
        }
        .frame(minHeight: 44)
        .font(.subheadline)
        .buttonStyle(.borderless)
    }

    private var currentHost: String {
        controller.session?.currentOrigin?.host ?? controller.session?.profile.homePageHost ?? ""
    }

    private var statusTitle: String {
        if controller.isPaused { return "已暂停" }
        if controller.isRefreshingBalance { return "更新余额" }
        switch controller.session?.automationState ?? .inactive {
        case .captcha: return "待验证"
        case .noButton: return "等待入口"
        case .error: return "检测失败"
        case .success, .skipped: return "已完成"
        case .inactive, .running: return "检测中"
        }
    }

    private var statusColor: Color {
        guard !controller.isPaused else { return .secondary }
        if controller.isRefreshingBalance { return .secondary }
        switch controller.session?.automationState ?? .inactive {
        case .captcha, .noButton: return .orange
        case .error: return .red
        case .success, .skipped: return .green
        case .inactive, .running: return .secondary
        }
    }

    private var results: some View {
        List {
            Section {
                Label(controller.queue.isFinished ? "本组已处理完毕" : "本组签到已停止", systemImage: controller.queue.isFinished ? "checkmark.circle" : "stop.circle")
                Text("已完成 \(controller.queue.completedCount) · 已跳过 \(controller.queue.skippedCount) · 未处理 \(controller.queue.profileIDs.count - controller.queue.index)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section("环境结果") {
                ForEach(controller.profiles) { profile in
                    LabeledContent(profile.name, value: outcomeTitle(for: profile.id))
                }
            }
        }
    }

    private func outcomeTitle(for id: UUID) -> String {
        switch controller.queue.outcomes[id] {
        case .completed: "签到完成"
        case .alreadyCompleted: "今天已完成"
        case .skipped: "已跳过"
        case nil: "未处理"
        }
    }

}
