import SwiftUI

@main
@MainActor
struct ProfileBrowserApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ProfileGroupGridView()
                .environment(model)
                .tint(Color("AccentColor"))
        }
    }
}
