import SwiftUI

struct FormField<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            content
        }
        .padding(.vertical, 4)
    }
}

struct InlineValidationMessage: View {
    let message: String

    var body: some View {
        Label {
            Text(message)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.red)
        }
        .font(.footnote)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct IntegerSettingField: View {
    let title: String
    @Binding var text: String
    let range: ClosedRange<Int>
    let unit: String
    @FocusState private var isFocused: Bool

    var body: some View {
        FormField(title) {
            HStack(spacing: 12) {
                TextField(title, text: $text)
                    .keyboardType(.numberPad)
                    .monospacedDigit()
                    .focused($isFocused)
                    .accessibilityLabel(title)
                Text(unit)
                    .foregroundStyle(.secondary)
                Stepper(title, value: numericValue, in: range)
                    .labelsHidden()
                    .accessibilityLabel("调整\(title)")
            }
            if !isValid {
                InlineValidationMessage(message: "请输入 \(range.lowerBound) 到 \(range.upperBound) 之间的整数。")
            }
        }
        .toolbar {
            if isFocused {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") { isFocused = false }
                }
            }
        }
    }

    private var isValid: Bool {
        Int(text).map { range.contains($0) } ?? false
    }

    private var numericValue: Binding<Int> {
        Binding(
            get: { min(range.upperBound, max(range.lowerBound, Int(text) ?? range.lowerBound)) },
            set: { text = String($0) }
        )
    }
}
