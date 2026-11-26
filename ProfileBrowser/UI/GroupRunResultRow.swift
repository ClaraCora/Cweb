import SwiftUI

struct GroupRunResultRow: View {
    let name: String
    let outcome: GroupCheckInQueue.Outcome?
    let detail: GroupEnvironmentResult?

    var body: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.tight) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: AppUI.Spacing.row) {
                    title.fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    status.fixedSize()
                }
                VStack(alignment: .leading, spacing: AppUI.Spacing.tight) {
                    title
                    status
                }
            }
            if let balance = detail?.balance {
                if case .failed = balance {
                    AppStatusMessage(message: balance.message, tone: .warning)
                } else {
                    Text(balance.message)
                        .font(.footnote)
                        .foregroundStyle(AppUI.secondaryText)
                }
            }
            if let detail, !detail.message.isEmpty, detail.message != outcome?.title, detail.balance?.message != detail.message {
                Text(detail.message)
                    .font(.footnote)
                    .foregroundStyle(AppUI.secondaryText)
            }
            if let duration = detail?.duration, duration > 0 {
                Text("耗时 \(Int(duration)) 秒")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(AppUI.secondaryText)
            }
        }
        .padding(.vertical, AppUI.Spacing.tight)
        .accessibilityElement(children: .combine)
    }

    private var title: some View {
        Text(name)
            .font(.body.weight(.medium))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var status: some View {
        AppStatusMessage(message: outcome?.title ?? "未处理", tone: tone, symbol: symbol)
    }

    private var tone: AppStatusMessage.Tone {
        switch outcome {
        case .completed, .alreadyCompleted, .balanceUpdated: .success
        case .failed: .warning
        case .skipped, nil: .neutral
        }
    }

    private var symbol: String? {
        switch outcome {
        case .skipped: "forward.end"
        case nil: "circle.dotted"
        default: nil
        }
    }
}

struct GroupRunCounts: View {
    let queue: GroupCheckInQueue

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppUI.Spacing.row) {
                processed
                remaining
            }
            .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: AppUI.Spacing.tight) {
                processed
                remaining
            }
        }
        .font(.footnote)
        .monospacedDigit()
        .foregroundStyle(AppUI.secondaryText)
        .accessibilityElement(children: .combine)
    }

    private var processed: some View {
        Text("完成 \(queue.completedCount) · 待处理 \(queue.failedCount)")
    }

    private var remaining: some View {
        Text("跳过 \(queue.skippedCount) · 未处理 \(queue.profileIDs.count - queue.index)")
    }
}
