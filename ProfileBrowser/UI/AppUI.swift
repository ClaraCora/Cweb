import SwiftUI

enum AppUI {
    enum Spacing {
        static let tight: CGFloat = 4
        static let related: CGFloat = 8
        static let row: CGFloat = 12
        static let page: CGFloat = 16
    }

    static let minimumTarget: CGFloat = 44
    static let readableWidth: CGFloat = 840
    static let secondaryText = Color("SecondaryText")
    static let success = Color("ProxyLatencyFast")
    static let warning = Color("ProxyLatencyModerate")
    static let danger = Color("ProxyLatencySlow")

    static func latencyColor(_ milliseconds: Int) -> Color {
        switch milliseconds {
        case ...500: success
        case ...2_000: warning
        default: danger
        }
    }
}

private struct ReadableListMargins: ViewModifier {
    let minimum: CGFloat

    func body(content: Content) -> some View {
        GeometryReader { geometry in
            content.contentMargins(
                .horizontal,
                max(minimum, (geometry.size.width - AppUI.readableWidth) / 2),
                for: .scrollContent
            )
        }
    }
}

extension View {
    /// Uses the actual window width, including iPad multitasking and rotation.
    func readableListMargins(minimum: CGFloat = 16) -> some View {
        modifier(ReadableListMargins(minimum: minimum))
    }
}

/// Keeps custom list rows responsive to touch without changing their bounds.
struct ListRowButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.6 : 1)
    }
}

struct AppSettingsRow: View {
    let title: String
    let detail: String?
    let icon: String

    init(_ title: String, detail: String? = nil, icon: String) {
        self.title = title
        self.detail = detail
        self.icon = icon
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: AppUI.Spacing.tight) {
                Text(title).foregroundStyle(.primary)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(AppUI.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } icon: {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
                .accessibilityHidden(true)
        }
        .padding(.vertical, AppUI.Spacing.tight)
        .frame(minHeight: AppUI.minimumTarget)
    }
}

struct AppStatusMessage: View {
    enum Tone {
        case success, warning, error

        var icon: String {
            switch self {
            case .success: "checkmark.circle"
            case .warning: "exclamationmark.circle"
            case .error: "exclamationmark.triangle"
            }
        }

        var color: Color {
            switch self {
            case .success: AppUI.success
            case .warning: AppUI.warning
            case .error: AppUI.danger
            }
        }
    }

    let message: String
    let tone: Tone

    var body: some View {
        Label {
            Text(message).foregroundStyle(.primary)
        } icon: {
            Image(systemName: tone.icon).foregroundStyle(tone.color)
        }
        .font(.footnote)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}
