import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct SocksProxyExportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    private var rankings: [SocksProxyRanking] { model.rankedSocksProxies }
    @State private var selectedIDs: Set<UUID>
    @State private var showsExporter = false
    @State private var document = SocksProxyExportDocument()
    @State private var presentedError: PresentedError?
    @State private var exported = false

    init(rankings: [SocksProxyRanking]) {
        _selectedIDs = State(initialValue: Set(rankings.map(\.id)))
    }

    var body: some View {
        NavigationStack {
            List(selection: $selectedIDs) {
                Section {
                    ForEach(rankings) { ranking in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(ranking.number) · \(ranking.proxy.displayCode ?? ranking.proxy.displayAddress)")
                            if let measurement = ranking.proxy.latestMeasurement {
                                Text(measurement.status == .available ? "\(measurement.latencyMilliseconds.map(String.init) ?? "—") ms" : "最近检测不可用")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(measurement.checkedAt, format: .dateTime.month().day().hour().minute())
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            if ranking.proxy.displayCode != nil {
                                Text(ranking.proxy.displayAddress)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .tag(ranking.id)
                    }
                } header: {
                    Text("已选择 \(selectedIDs.count) / \(rankings.count) 个")
                } footer: {
                    Text("导出为 TXT，每行一个 SOCKS 链接。文件包含所选代理的账号和密码，请妥善保存。")
                }
            }
            .environment(\.editMode, .constant(.active))
            .onChange(of: rankings.map(\.id)) { _, ids in selectedIDs.formIntersection(Set(ids)) }
            .navigationTitle("批量导出")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("选择", systemImage: "checklist") {
                        Button("全选") { selectedIDs = Set(rankings.map(\.id)) }
                        Button("仅选可用") {
                            selectedIDs = Set(rankings.filter { $0.proxy.isAvailable }.map(\.id))
                        }
                        Button("取消全选") { selectedIDs.removeAll() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导出") { export() }
                        .disabled(selectedIDs.isEmpty)
                }
            }
            .fileExporter(
                isPresented: $showsExporter,
                document: document,
                contentType: .plainText,
                defaultFilename: "Cweb-proxies.txt"
            ) { result in
                switch result {
                case .success:
                    exported = true
                case .failure(let error):
                    if (error as? CocoaError)?.code != .userCancelled {
                        presentedError = PresentedError(message: error.localizedDescription)
                    }
                }
                document = SocksProxyExportDocument()
            }
            .alert("导出完成", isPresented: $exported) {
                Button("好", role: .cancel) {}
            }
            .alert(item: $presentedError) { error in
                Alert(title: Text("导出失败"), message: Text(error.message), dismissButton: .default(Text("好")))
            }
        }
    }

    private func export() {
        do {
            document = SocksProxyExportDocument(text: try SocksProxyExport.text(
                for: rankings.filter { selectedIDs.contains($0.id) }.map(\.proxy)
            ))
            showsExporter = true
        } catch {
            presentedError = PresentedError(message: error.localizedDescription)
        }
    }
}
