import SwiftUI

@MainActor
struct SocksProxyListView: View {
    @Environment(AppModel.self) private var model

    @State private var editorMode: SocksProxyEditorMode?
    @State private var showsImport = false
    @State private var showsPresets = false
    @State private var pendingClear = false
    @State private var pendingDelete: SocksProxy?
    @State private var isValidating = false
    @State private var statusMessage: String?

    var body: some View {
        @Bindable var model = model

        List {
            proxySection
            presetSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("SOCKS 代理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("验证", systemImage: "bolt.horizontal") {
                    validateProxies()
                }
                .disabled(model.socksProxies.isEmpty || isValidating)

                Menu {
                    Button("从链接导入", systemImage: "link.badge.plus") {
                        showsImport = true
                    }
                    Button("添加代理", systemImage: "plus") {
                        editorMode = .create
                    }
                    Button("管理预设链接", systemImage: "list.bullet.rectangle") {
                        showsPresets = true
                    }
                    Divider()
                    Button("清空全部代理", systemImage: "trash", role: .destructive) {
                        pendingClear = true
                    }
                    .disabled(model.socksProxies.isEmpty || isValidating)
                } label: {
                    Label("更多", systemImage: "ellipsis.circle")
                }
            }
        }
        .overlay {
            if isValidating {
                ProgressView("正在验证")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .sheet(item: $editorMode) { mode in
            SocksProxyEditorView(proxy: mode.proxy) { proxy in
                if mode.proxy == nil {
                    try model.addSocksProxy(proxy)
                } else {
                    try model.updateSocksProxy(proxy)
                }
            }
        }
        .sheet(isPresented: $showsImport) {
            SocksProxyImportView { url in
                try await model.importSocksProxies(from: url)
            }
        }
        .sheet(isPresented: $showsPresets) {
            SocksProxyPresetListView()
        }
        .alert("清空全部代理？", isPresented: $pendingClear) {
            Button("清空", role: .destructive) {
                do {
                    try model.clearSocksProxies()
                    statusMessage = "已清空代理列表。"
                } catch {
                    model.present(error)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除当前保存的所有 SOCKS 代理记录。环境保留已选择的编号，重新导入代理后会继续按该编号使用。")
        }
        .alert("删除代理？", isPresented: deleteAlertBinding, presenting: pendingDelete) { proxy in
            Button("删除", role: .destructive) {
                pendingDelete = nil
                do {
                    try model.deleteSocksProxy(proxy)
                } catch {
                    model.present(error)
                }
            }
            Button("取消", role: .cancel) {}
        } message: { proxy in
            Text("将删除 \(proxy.displayAddress)。")
        }
        .alert("操作完成", isPresented: statusAlertBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(statusMessage ?? "")
        }
        .alert(item: $model.presentedError) { error in
            Alert(
                title: Text("操作失败"),
                message: Text(error.message),
                dismissButton: .default(Text("好"))
            )
        }
    }

    @ViewBuilder
    private var proxySection: some View {
        Section {
            if rankedProxies.isEmpty {
                ContentUnavailableView {
                    Label("还没有代理", systemImage: "network")
                } description: {
                    Text("可从订阅链接导入，或手动添加一个 SOCKS 代理。")
                } actions: {
                    Button("导入代理", systemImage: "link.badge.plus") {
                        showsImport = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                ForEach(rankedProxies) { ranking in
                    SocksProxyRow(ranking: ranking) {
                        editorMode = .edit(ranking.proxy)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("删除", systemImage: "trash", role: .destructive) {
                            pendingDelete = ranking.proxy
                        }
                        Button("编辑", systemImage: "pencil") {
                            editorMode = .edit(ranking.proxy)
                        }
                        .tint(.indigo)
                    }
                    .contextMenu {
                        Button("编辑代理", systemImage: "pencil") {
                            editorMode = .edit(ranking.proxy)
                        }
                        Button("删除代理", systemImage: "trash", role: .destructive) {
                            pendingDelete = ranking.proxy
                        }
                    }
                }
                .onDelete { offsets in
                    let values = offsets.compactMap { rankedProxies[safe: $0]?.proxy }
                    for proxy in values {
                        do {
                            try model.deleteSocksProxy(proxy)
                        } catch {
                            model.present(error)
                            break
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text("代理列表")
                Spacer()
                Text("验证后按延迟排序")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var presetSection: some View {
        Section {
            if model.proxyPresets.isEmpty {
                Button("添加预设链接", systemImage: "plus") {
                    showsPresets = true
                }
            } else {
                ForEach(model.proxyPresets) { preset in
                    HStack(spacing: 12) {
                        Image(systemName: preset.isEnabled ? "link" : "link.slash")
                            .foregroundStyle(preset.isEnabled ? Color.accentColor : .secondary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.displayName)
                                .lineLimit(1)
                            Text(preset.url.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Button("拉取", systemImage: "arrow.down.circle") {
                            importPreset(preset)
                        }
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(!preset.isEnabled || isValidating)
                        .accessibilityLabel("拉取 \(preset.displayName)")
                    }
                }
            }
        } header: {
            HStack {
                Text("预设链接")
                Spacer()
                Button("管理", systemImage: "slider.horizontal.3") {
                    showsPresets = true
                }
                .font(.caption)
                .textCase(nil)
            }
        } footer: {
            Text("预设链接只会在你点击“拉取”时访问网络，可保存多个来源。")
        }
    }

    private var rankedProxies: [SocksProxyRanking] {
        SocksProxyValidationService.ranked(model.socksProxies)
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    private var statusAlertBinding: Binding<Bool> {
        Binding(
            get: { statusMessage != nil },
            set: { if !$0 { statusMessage = nil } }
        )
    }

    private func validateProxies() {
        guard !isValidating else { return }
        isValidating = true
        Task { @MainActor in
            defer { isValidating = false }
            do {
                try await model.validateSocksProxies()
            } catch {
                model.present(error)
            }
        }
    }

    private func importPreset(_ preset: SocksProxyPreset) {
        guard !isValidating else { return }
        isValidating = true
        Task { @MainActor in
            defer { isValidating = false }
            do {
                try await model.importSocksProxies(from: preset.url)
                statusMessage = "已拉取 \(preset.displayName)。"
            } catch {
                model.present(error)
            }
        }
    }
}

private struct SocksProxyRow: View {
    let ranking: SocksProxyRanking
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text("\(ranking.number)")
                    .font(.headline.monospacedDigit().weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(width: 30, height: 30)
                    .background(Color.accentColor.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(ranking.proxy.displayAddress)
                        .font(.body.monospaced())
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        statusLabel
                        if let latency = ranking.proxy.latencyMilliseconds {
                            Text("\(latency) ms")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if ranking.proxy.username != nil {
                            Image(systemName: "person.badge.key")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("需要认证")
                        }
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("第 \(ranking.number) 号，\(ranking.proxy.displayAddress)，\(statusText)")
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch ranking.proxy.status {
        case .available:
            Label("可用", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .unavailable:
            Label("不可用", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .untested:
            Label("未验证", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        switch ranking.proxy.status {
        case .available: "可用"
        case .unavailable: "不可用"
        case .untested: "未验证"
        }
    }
}

@MainActor
private struct SocksProxyPresetListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var editorPreset: SocksProxyPresetEditorMode?
    @State private var pendingDelete: SocksProxyPreset?

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            List {
                if model.proxyPresets.isEmpty {
                    ContentUnavailableView {
                        Label("还没有预设链接", systemImage: "link.badge.plus")
                    } actions: {
                        Button("添加预设链接", systemImage: "plus") {
                            editorPreset = .create
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    ForEach(model.proxyPresets) { preset in
                        HStack(spacing: 12) {
                            Toggle(
                                isOn: Binding(
                                    get: { preset.isEnabled },
                                    set: { value in
                                        var updated = preset
                                        updated.isEnabled = value
                                        do {
                                            try model.updateProxyPreset(updated)
                                        } catch {
                                            model.present(error)
                                        }
                                    }
                                )
                            ) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(preset.displayName)
                                        .lineLimit(1)
                                    Text(preset.url.absoluteString)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("删除", systemImage: "trash", role: .destructive) {
                                pendingDelete = preset
                            }
                            Button("编辑", systemImage: "pencil") {
                                editorPreset = .edit(preset)
                            }
                            .tint(.indigo)
                        }
                        .contextMenu {
                            Button("编辑链接", systemImage: "pencil") {
                                editorPreset = .edit(preset)
                            }
                            Button("删除链接", systemImage: "trash", role: .destructive) {
                                pendingDelete = preset
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets.sorted(by: >) {
                            guard model.proxyPresets.indices.contains(index) else { continue }
                            do {
                                try model.deleteProxyPreset(model.proxyPresets[index])
                            } catch {
                                model.present(error)
                                break
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("预设链接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加", systemImage: "plus") {
                        editorPreset = .create
                    }
                }
            }
            .sheet(item: $editorPreset) { mode in
                SocksProxyPresetEditorView(preset: mode.preset) { preset in
                    try model.updateOrAddProxyPreset(preset)
                }
            }
            .alert("删除预设链接？", isPresented: deleteAlertBinding, presenting: pendingDelete) { preset in
                Button("删除", role: .destructive) {
                    pendingDelete = nil
                    do {
                        try model.deleteProxyPreset(preset)
                    } catch {
                        model.present(error)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: { preset in
                Text("将删除“\(preset.displayName)”的保存链接。")
            }
            .alert(item: $model.presentedError) { error in
                Alert(
                    title: Text("操作失败"),
                    message: Text(error.message),
                    dismissButton: .default(Text("好"))
                )
            }
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }
}

private enum SocksProxyEditorMode: Identifiable {
    case create
    case edit(SocksProxy)

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let proxy): proxy.id.uuidString
        }
    }

    var proxy: SocksProxy? {
        switch self {
        case .create: nil
        case .edit(let proxy): proxy
        }
    }
}

private enum SocksProxyPresetEditorMode: Identifiable {
    case create
    case edit(SocksProxyPreset)

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let preset): preset.id.uuidString
        }
    }

    var preset: SocksProxyPreset? {
        switch self {
        case .create: nil
        case .edit(let preset): preset
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
