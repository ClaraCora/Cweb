import SwiftUI

struct GroupCheckInControls: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let canStart: Bool
    let canPause: Bool
    let canStop: Bool
    let start: () -> Void
    let pause: () -> Void
    let stop: () -> Void
    var isCompact = false

    @ViewBuilder
    var body: some View {
        if isCompact {
            HStack(spacing: 4) {
                Button(action: start) { Text("开始").frame(minWidth: 44, minHeight: 44) }
                    .disabled(!canStart)
                    .accessibilityHint("开始或继续本组顺序签到")
                Button(action: pause) { Text("暂停").frame(minWidth: 44, minHeight: 44) }
                    .disabled(!canPause)
                Button(action: stop) { Text("停止").frame(minWidth: 44, minHeight: 44) }
                    .tint(.red)
                    .disabled(!canStop)
            }
            .font(.subheadline.weight(.medium))
            .buttonStyle(.borderless)
        } else {
            standardControls
        }
    }

    private var standardControls: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) { buttons }
            } else {
                HStack(spacing: 12) { buttons }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private var buttons: some View {
        Button(action: start) { Text("开始").frame(maxWidth: .infinity, minHeight: 32) }
            .buttonStyle(.borderedProminent)
            .disabled(!canStart)
            .accessibilityHint("开始或继续本组顺序签到")
        Button(action: pause) { Text("暂停").frame(maxWidth: .infinity, minHeight: 32) }
            .buttonStyle(.bordered)
            .disabled(!canPause)
        Button(action: stop) { Text("停止").frame(maxWidth: .infinity, minHeight: 32) }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(!canStop)
    }
}
