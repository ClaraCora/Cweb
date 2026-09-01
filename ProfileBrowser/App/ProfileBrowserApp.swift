import SwiftUI

@main
@MainActor
struct ProfileBrowserApp: App {
    @State private var model = AppModel()
    @AppStorage(AppSettings.appearanceModeKey) private var appearanceModeRaw = AppSettings.defaultAppearanceMode

    private var preferredColorScheme: ColorScheme? {
        switch AppAppearanceMode(rawValue: appearanceModeRaw) ?? .system {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(model)
                .tint(Color("AccentColor"))
                .preferredColorScheme(preferredColorScheme)
        }
    }
}
