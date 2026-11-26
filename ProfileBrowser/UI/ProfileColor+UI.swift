import SwiftUI

struct ProfileGroupIcon: View {
    let emoji: String?
    var size: CGFloat = AppUI.minimumTarget

    var body: some View {
        Group {
            if let emoji = emoji?.trimmingCharacters(in: .whitespacesAndNewlines), !emoji.isEmpty {
                Text(emoji)
                    .font(.title2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            } else {
                Image(systemName: "folder.fill")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: size, height: size)
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
    }
}

extension ProfileColor {
    var color: Color {
        switch self {
        case .indigo: .indigo
        case .teal: .teal
        case .green: .green
        case .orange: .orange
        case .pink: .pink
        case .red: .red
        }
    }

    var title: String {
        switch self {
        case .indigo: "靛蓝"
        case .teal: "青色"
        case .green: "绿色"
        case .orange: "橙色"
        case .pink: "粉色"
        case .red: "红色"
        }
    }
}
