import SwiftUI

struct GroupRunResultRow: View {
    let name: String
    let outcome: GroupCheckInQueue.Outcome?
    let detail: GroupEnvironmentResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(name, value: outcome?.title ?? "未处理")
            if let balance = detail?.balance {
                Text(balance.message).font(.footnote)
                    .foregroundStyle(balanceFailed ? AppUI.danger : .secondary)
            }
            if let detail, !detail.message.isEmpty {
                Text(detail.message).font(.footnote).foregroundStyle(.secondary)
            }
            if let duration = detail?.duration, duration > 0 {
                Text("耗时 \(Int(duration)) 秒").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var balanceFailed: Bool {
        if case .failed = detail?.balance { return true }
        return false
    }
}
