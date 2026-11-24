import SwiftUI

@MainActor
struct GroupCheckInView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(AppModel.self) private var model
    @State private var retryController: GroupCheckInController?
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
                        automaticallyRefreshesBalance: controller.mode != .balanceOnly,
                        browserChromePresentation: $showsBrowserChrome
                    ) { [weak run = controller] id, event in
                        run?.receive(id, event)
                    }
                        .id(session.profile.id)
                } else if !controller.hasStarted {
                    preflight
                } else {
                    results
                }
            }
            .navigationTitle(navigationTitle)
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
        .sheet(item: $retryController) { GroupCheckInView(controller: $0) }
        .onChange(of: controller.session?.automationState) { _, state in
            if state == .error || state == .noButton || state == .captcha { showsTaskDetails = true }
        }
        .onChange(of: controller.session?.profile.id) { _, _ in
            showsBrowserChrome = false
            showsTaskDetails = false
        }
        .onDisappear { controller.pause() }
    }

    private var navigationTitle: String {
        if let session = controller.session { return session.profile.name }
        if !controller.hasStarted { return "开始前确认" }
        return controller.groupName + (controller.mode == .balanceOnly ? "余额结果" : "签到结果")
    }

    private var preflight: some View {
        List {
            Section("开始前确认") {
                if controller.preflightIssues.isEmpty {
                    Text("以下环境的入口或网络路径发生变化，请确认后开始。")
                } else {
                    ForEach(controller.preflightIssues, id: \.self) { Text($0) }
                    Text("可以返回编辑相关环境，或将异常环境标记为待处理后继续。")
                }
                ForEach(controller.changedEntries) { profile in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.name).font(.headline)
                        Text(profile.homePageHost)
                        Text(model.socksProxy(for: profile).map { $0.displayCode ?? $0.displayAddress } ?? "设备网络")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Button("确认并开始") { controller.confirmAndStart() }
                    .disabled(!controller.preflightIssues.isEmpty)
                if !controller.preflightIssues.isEmpty {
                    Button("异常项待处理，开始其余环境") { controller.excludeUnavailableAndStart() }
                        .accessibilityIdentifier("groupCheckIn.startAvailable")
                }
            }
        }
    }

    private var taskBar: some View {
        let status = GroupTaskStatus.current(controller)
        return VStack(spacing: 0) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 0) {
                    taskSummary(status)
                    taskControls.frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                HStack(spacing: 8) {
                    taskSummary(status)
                    taskControls
                }
            }
            if showsTaskDetails {
                Divider()
                taskDetails
                    .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, AppUI.Spacing.row)
        .frame(maxWidth: AppUI.readableWidth - 2 * AppUI.Spacing.page)
        .beamPanel(cornerRadius: 14, active: status.running)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AppUI.Spacing.page)
        .padding(.vertical, 4)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var taskControls: some View {
        GroupCheckInControls(
            canStart: controller.canStart, canPause: controller.canPause, canStop: controller.canStop,
            start: controller.start, pause: controller.pause, stop: controller.stop
        )
        .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
    }

    private func taskSummary(_ status: GroupTaskStatus) -> some View {
        Button {
            showsTaskDetails.toggle()
        } label: {
            HStack(spacing: 6) {
                status.icon
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(controller.queue.index + 1)/\(controller.queue.profileIDs.count)")
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Text(status.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(status.tint)
                }
                .lineLimit(1)
                Image(systemName: showsTaskDetails ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(AppUI.secondaryText)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("本组第 \(controller.queue.index + 1) 个，共 \(controller.queue.profileIDs.count) 个，\(status.title)，\(currentHost)")
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
                Text("已完成 \(controller.queue.completedCount) · 待处理 \(controller.queue.failedCount) · 已跳过 \(controller.queue.skippedCount)")
                    .font(.footnote)
                    .foregroundStyle(AppUI.secondaryText)
            }
            ProgressView(value: Double(controller.queue.index), total: Double(max(1, controller.queue.profileIDs.count)))
            if let message = controller.session?.automationMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
            }
            if controller.isPaused {
                Text("点击“开始”继续当前任务。")
                    .font(.caption)
                    .foregroundStyle(AppUI.secondaryText)
            }
            if let session = controller.session, session.automationState == .captcha {
                HStack {
                    Text("手动完成验证后继续。")
                        .font(.caption)
                        .foregroundStyle(AppUI.secondaryText)
                    Spacer()
                    Button("继续检测") { Task { await session.resumeAutomation() } }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44)
                        .disabled(controller.isPaused)
                        .accessibilityIdentifier("groupCheckIn.resumeCaptcha")
                }
                .font(.footnote.weight(.semibold))
            }
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

    private var results: some View {
        List {
            Section {
                Label(controller.queue.isFinished ? "本组已处理完毕" : (controller.mode == .balanceOnly ? "余额更新已停止" : "本组签到已停止"), systemImage: controller.queue.isFinished ? "checkmark.circle" : "stop.circle")
                Text("已完成 \(controller.queue.completedCount) · 待处理 \(controller.queue.failedCount) · 已跳过 \(controller.queue.skippedCount) · 未处理 \(controller.queue.profileIDs.count - controller.queue.index)")
                    .font(.subheadline)
                    .foregroundStyle(AppUI.secondaryText)
            }
            Section {
                Button("重试未完成项") { retry(balanceOnly: false) }
                    .disabled(controller.record.retryProfileIDs.isEmpty)
                Button("仅重试余额") { retry(balanceOnly: true) }
                    .disabled(controller.record.balanceRetryProfileIDs.isEmpty)
            }
            Section("环境结果") {
                ForEach(controller.profiles) { profile in
                    GroupRunResultRow(name: profile.name, outcome: controller.queue.outcomes[profile.id], detail: controller.details[profile.id])
                }
            }
        }
    }

    private func retry(balanceOnly: Bool) {
        let next = model.retryGroupRun(controller.record, balanceOnly: balanceOnly)
        next.start()
        retryController = next
    }
}
