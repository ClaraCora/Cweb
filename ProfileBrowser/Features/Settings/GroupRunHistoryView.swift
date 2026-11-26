import SwiftUI

struct GroupRunHistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmsDiscard = false
    @State private var retryController: GroupCheckInController?
    var body: some View {
        List {
            if let pending = model.pendingGroupRun {
                Section("可恢复任务") {
                    VStack(alignment: .leading, spacing: AppUI.Spacing.tight) {
                        Text(pending.groupName).font(.headline)
                        GroupRunCounts(queue: pending.queue)
                        Text("进入该分组，点击“开始”继续。")
                            .font(.footnote).foregroundStyle(AppUI.secondaryText)
                    }
                    Button("放弃剩余任务", role: .destructive) { confirmsDiscard = true }
                }
            }
            ForEach(model.groupRunHistory) { record in
                Section {
                    VStack(alignment: .leading, spacing: AppUI.Spacing.related) {
                        VStack(alignment: .leading, spacing: AppUI.Spacing.tight) {
                            Text(record.groupName).font(.headline)
                            Text(record.updatedAt, format: .dateTime.year().month().day().hour().minute())
                                .font(.caption).foregroundStyle(AppUI.secondaryText)
                        }
                        GroupRunCounts(queue: record.queue)
                    }
                    .padding(.vertical, AppUI.Spacing.tight)
                    ForEach(record.queue.profileIDs, id: \.self) { id in
                        GroupRunResultRow(name: record.details?[id]?.name ?? model.profiles.first(where: { $0.id == id })?.name ?? "已删除环境",
                            outcome: record.queue.outcomes[id], detail: record.details?[id])
                    }
                    Button("重试未完成项") { retry(record, balanceOnly: false) }
                        .disabled(record.retryProfileIDs.isEmpty)
                    Button("仅重试余额") { retry(record, balanceOnly: true) }
                        .disabled(record.balanceRetryProfileIDs.isEmpty)
                }
            }
        }
        .overlay {
            if model.groupRunHistory.isEmpty && model.pendingGroupRun == nil {
                ContentUnavailableView("暂无任务记录", systemImage: "clock", description: Text("分组签到或批量更新余额后，即可在这里查看结果。"))
            }
        }
        .sheet(item: $retryController) { GroupCheckInView(controller: $0) }
        .navigationTitle("签到记录").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("停止并归档剩余任务？", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("停止任务", role: .destructive) { model.discardPendingGroupRun() }
        }
    }
    private func retry(_ record: GroupRunRecord, balanceOnly: Bool) {
        let next = model.retryGroupRun(record, balanceOnly: balanceOnly)
        next.start()
        retryController = next
    }

}
