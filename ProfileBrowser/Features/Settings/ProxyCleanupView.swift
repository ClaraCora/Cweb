import SwiftUI

@MainActor
struct ProxyCleanupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var ids: Set<UUID> = []
    @State private var showsConfirmation = false
    @State private var error: PresentedError?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(model.proxyDeletionImpact(for: ids))
                    Text("测速仅更新结果。以下列表根据已保存的保留规则生成，锁定代理不会删除。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("待清理 \(ids.count) 个") {
                    ForEach(model.socksProxies.filter { ids.contains($0.id) }) { proxy in
                        Text(proxy.displayCode ?? proxy.displayAddress)
                    }
                }
            }
            .onAppear { ids = model.proxyCleanupIDs }
            .navigationTitle("清理预览").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("清理", role: .destructive) { showsConfirmation = true }.disabled(ids.isEmpty)
                }
            }
            .alert(item: $error) { Alert(title: Text("清理失败"), message: Text($0.message), dismissButton: .default(Text("好"))) }
            .confirmationDialog("确认清理预览中的代理？", isPresented: $showsConfirmation, titleVisibility: .visible) {
                Button("删除 \(ids.count) 个代理", role: .destructive) {
                    do { try model.deleteSocksProxies(withIDs: ids); dismiss() }
                    catch { self.error = PresentedError(message: error.localizedDescription) }
                }
            }
        }
    }
}
