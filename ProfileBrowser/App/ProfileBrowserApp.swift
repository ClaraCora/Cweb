import SwiftUI

@main
@MainActor
struct ProfileBrowserApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AppModel.launchModel()
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
                .overlay {
                    if scenePhase != .active {
                        ZStack {
                            Color(uiColor: .systemBackground).ignoresSafeArea()
                            Label("环境浏览器", systemImage: "lock.shield").font(.title2)
                        }
                        .accessibilityIdentifier("privacy.cover")
                    }
                }
        }
    }
}
