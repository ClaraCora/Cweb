import SwiftUI

enum AppUI {
    enum Spacing {
        static let tight: CGFloat = 4
        static let related: CGFloat = 8
        static let row: CGFloat = 12
        static let page: CGFloat = 16
    }

    static let workspaceInset: CGFloat = 20
    static let panelRadius: CGFloat = 16
    static let overviewRadius: CGFloat = 18
    static let rowIconSize: CGFloat = 36
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

/// A shared visual hierarchy and press state for the two workspace actions.
struct WorkspaceActionStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(prominent ? Color(.systemBackground) : Color.accentColor)
            .frame(maxWidth: .infinity, minHeight: AppUI.minimumTarget)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(prominent ? Color.accentColor : Color(.quaternarySystemFill))
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.45)
    }
}

/// Keep custom row content responsive to touch without replacing native gestures.
struct WorkspaceRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct AppSettingsRow: View {
    let title: String
    let detail: String?
    let icon: String
    let tint: Color
    let status: String?

    init(_ title: String, detail: String? = nil, icon: String, tint: Color = .accentColor, status: String? = nil) {
        self.title = title
        self.detail = detail
        self.icon = icon
        self.tint = tint
        self.status = status
    }

    var body: some View {
        HStack(spacing: AppUI.Spacing.row) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: AppUI.rowIconSize, height: AppUI.rowIconSize)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppUI.Spacing.tight) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(AppUI.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let status {
                Text(status)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppUI.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(.tertiarySystemFill), in: Capsule())
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, AppUI.Spacing.page)
        .padding(.vertical, AppUI.Spacing.row)
        .frame(minHeight: 68)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct AppStatusMessage: View {
    enum Tone {
        case neutral, success, warning, error

        var icon: String {
            switch self {
            case .neutral: "info.circle"
            case .success: "checkmark.circle"
            case .warning: "exclamationmark.circle"
            case .error: "exclamationmark.triangle"
            }
        }

        var color: Color {
            switch self {
            case .neutral: AppUI.secondaryText
            case .success: AppUI.success
            case .warning: AppUI.warning
            case .error: AppUI.danger
            }
        }
    }

    let message: String
    let tone: Tone
    var symbol: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppUI.Spacing.related) {
            Image(systemName: symbol ?? tone.icon)
                .foregroundStyle(tone.color)
                .accessibilityHidden(true)
            Text(message).foregroundStyle(.primary)
        }
        .font(.footnote)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}
