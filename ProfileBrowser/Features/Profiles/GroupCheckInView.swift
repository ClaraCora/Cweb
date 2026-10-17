import SwiftUI

@MainActor
struct GroupCheckInView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let controller: GroupCheckInController

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let session = controller.session {
                    GroupCheckInControls(
                        canStart: controller.canStart, canPause: controller.canPause, canStop: controller.canStop,
                        start: controller.start, pause: controller.pause,
                        stop: controller.stop
                    )
                    runProgress
                    BrowserView(session: session, automationSettings: controller.settings, automationIsPaused: controller.isPaused) { [weak run = controller] id, event in
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
                    Button(controller.session == nil ? "完成" : "返回分组") {
                        controller.pause()
                        dismiss()
                    }
                }
                if controller.session != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("跳过") { controller.skip() }
                    }
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
        .onDisappear { controller.pause() }
    }

    private var runProgress: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(controller.groupName) · \(controller.queue.index + 1) / \(controller.queue.profileIDs.count)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(controller.isPaused ? "已暂停" : "已完成 \(controller.queue.completedCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(controller.queue.index), total: Double(max(1, controller.queue.profileIDs.count)))
            Text(controller.isPaused ? "继续后恢复自动检测。" : "每 5 秒重新检测；验证码请手动完成，确认签到后自动进入下一个。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
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
