import SwiftUI

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
