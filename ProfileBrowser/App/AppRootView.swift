import SwiftUI

@MainActor
struct AppRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TabView {
            ProfileGroupGridView()
                .tabItem {
                    Label("分组", systemImage: "square.grid.2x2")
                }

            NavigationStack {
                SocksProxyListView()
            }
            .tabItem {
                Label("代理", systemImage: "network")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("设置", systemImage: "gearshape")
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .background { model.activeGroupRun?.pause() } }
        .task {
            if !model.isProfileStoreAvailable { await model.retryLoadingProfiles() }
            await model.cleanOrphanedWebsiteDataOnColdLaunch()
        }
    }
}
