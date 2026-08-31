import Foundation

/// App-wide preferences stored in UserDefaults. Keeping the keys in one place
/// makes settings screens and the app scene use the exact same values.
enum AppAppearanceMode: String, CaseIterable, Identifiable, Hashable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }
}

enum AppSettings {
    static let appearanceModeKey = "app.appearanceMode"

    static let defaultAppearanceMode = AppAppearanceMode.system.rawValue
}
