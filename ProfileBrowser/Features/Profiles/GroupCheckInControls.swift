import SwiftUI

// The list and the open browser describe the same session. Derive their
// wording, symbol, and motion from one snapshot of its actual activity.
struct GroupTaskStatus {
    let title: String
    let symbol: String
    let tint: Color
    var running = false

    @MainActor
    static func current(_ controller: GroupCheckInController) -> Self {
        if controller.isPaused { return Self(title: "已暂停", symbol: "pause.fill", tint: AppUI.secondaryText) }
        if controller.isRefreshingBalance || controller.mode == .balanceOnly {
            return Self(title: "更新余额", symbol: "arrow.triangle.2.circlepath", tint: .accentColor, running: true)
        }
        switch controller.session?.automationState ?? .inactive {
        case .inactive, .running: return Self(title: "检测中", symbol: "scope", tint: .accentColor, running: true)
        case .captcha: return Self(title: "待验证", symbol: "hand.raised.fill", tint: AppUI.warning)
        case .noButton: return Self(title: "等待入口", symbol: "clock", tint: AppUI.warning)
        case .error: return Self(title: "检测失败", symbol: "exclamationmark.triangle.fill", tint: AppUI.danger)
        case .success, .skipped: return Self(title: "已完成", symbol: "checkmark.circle.fill", tint: AppUI.success)
        }
    }

    var icon: some View {
        Image(systemName: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct GroupCheckInControls: View {
    let canStart: Bool
    let canPause: Bool
    let canStop: Bool
    let start: () -> Void
    let pause: () -> Void
    let stop: () -> Void
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppUI.Spacing.related) { buttons }
                .fixedSize(horizontal: true, vertical: false)
            VStack(spacing: 0) { buttons }
        }
        .font(.subheadline.weight(.medium))
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private var buttons: some View {
        Button(action: start) { controlLabel("开始") }
            .disabled(!canStart)
            .accessibilityHint("开始或继续本组任务")
            .accessibilityIdentifier("groupCheckIn.start")
        Button(action: pause) { controlLabel("暂停") }
            .disabled(!canPause)
            .accessibilityIdentifier("groupCheckIn.pause")
        Button(action: stop) { controlLabel("停止") }
            .tint(AppUI.danger)
            .disabled(!canStop)
            .accessibilityIdentifier("groupCheckIn.stop")
    }

    private func controlLabel(_ title: String) -> some View {
        Text(title)
            .fixedSize(horizontal: true, vertical: false)
            .frame(
                minWidth: AppUI.minimumTarget,
                minHeight: AppUI.minimumTarget
            )
            .contentShape(Rectangle())
    }
}
