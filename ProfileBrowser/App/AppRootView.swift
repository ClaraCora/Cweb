import SwiftUI

@MainActor
struct AppRootView: View {
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
    }
}
