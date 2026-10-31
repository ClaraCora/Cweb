import SwiftUI

struct GroupCheckInControls: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let canStart: Bool
    let canPause: Bool
    let canStop: Bool
    let start: () -> Void
    let pause: () -> Void
    let stop: () -> Void
    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 0) { buttons }
            } else {
                HStack(spacing: 2) { buttons }
            }
        }
        .font(.subheadline.weight(.medium))
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private var buttons: some View {
        Button(action: start) { controlLabel("开始") }
            .disabled(!canStart)
            .accessibilityHint("开始或继续本组顺序签到")
            .accessibilityIdentifier("groupCheckIn.start")
        Button(action: pause) { controlLabel("暂停") }
            .disabled(!canPause)
            .accessibilityIdentifier("groupCheckIn.pause")
        Button(action: stop) { controlLabel("停止") }
            .tint(.red)
            .disabled(!canStop)
            .accessibilityIdentifier("groupCheckIn.stop")
    }

    private func controlLabel(_ title: String) -> some View {
        Text(title)
            .frame(
                minWidth: 44,
                maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil,
                minHeight: 44
            )
            .contentShape(Rectangle())
    }
}
