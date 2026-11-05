import SwiftUI

struct GroupRunHistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmsDiscard = false
    var body: some View {
        List {
            if let pending = model.pendingGroupRun {
                Section("可恢复任务") {
                    Text(pending.groupName)
                    Text("已处理 \(pending.queue.index)/\(pending.queue.profileIDs.count)；进入该分组点击开始以继续。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("放弃剩余任务", role: .destructive) { confirmsDiscard = true }
                }
            }
            ForEach(model.groupRunHistory) { record in
                Section {
                    Text(record.groupName).font(.headline)
                    Text(record.updatedAt, format: .dateTime.year().month().day().hour().minute())
                    Text("完成 \(record.queue.completedCount) · 跳过 \(record.queue.skippedCount) · 未处理 \(record.queue.profileIDs.count - record.queue.index)")
                    ForEach(record.queue.profileIDs, id: \.self) { id in
                        LabeledContent(model.profiles.first(where: { $0.id == id })?.name ?? "已删除环境", value: record.queue.outcomes[id].map {
                            switch $0 { case .completed: "完成"; case .alreadyCompleted: "今日已完成"; case .skipped: "跳过" }
                        } ?? record.statuses[id] ?? "未处理")
                    }
                }
            }
            if model.groupRunHistory.isEmpty && model.pendingGroupRun == nil { ContentUnavailableView("暂无任务记录", systemImage: "clock") }
        }
        .navigationTitle("签到记录").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("停止并归档剩余任务？", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("停止任务", role: .destructive) { model.discardPendingGroupRun() }
        }
    }
}
