import SwiftUI

@MainActor
struct SocksProxyListView: View {
    @Environment(AppModel.self) private var model

    @State private var editorMode: SocksProxyEditorMode?
    @State private var showsImport = false
    @State private var showsPresets = false
    @State private var showsBatchDelete = false
    @State private var pendingClear = false
    @State private var pendingDelete: SocksProxy?
    @State private var isValidating = false
    @State private var testingProxyID: UUID?
    @State private var statusMessage: String?

    var body: some View {
        @Bindable var model = model

        List {
            proxySection
            presetSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("代理")
        .navigationBarTitleDisplayMode(.large)
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
                    Button("批量删除", systemImage: "checklist") {
                        showsBatchDelete = true
                    }
                    .disabled(unlockedProxyCount == 0 || isValidating)
                    Button("清空未锁定代理", systemImage: "trash", role: .destructive) {
                        pendingClear = true
                    }
                    .disabled(unlockedProxyCount == 0 || isValidating)
                } label: {
                    Label("更多", systemImage: "ellipsis.circle")
                }
            }
        }
        .overlay {
            if isValidating {
                ProgressView(
                    testingProxyID == nil ? "正在批量验证" : "正在测试代理"
                )
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .sheet(item: $editorMode) { mode in
            SocksProxyEditorView(proxy: mode.proxy, isCopy: mode.isCopy) { proxy in
                if mode.createsNewRecord {
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
        .sheet(isPresented: $showsBatchDelete) {
            SocksProxyBatchDeleteView { deletedCount in
                statusMessage = "已删除 \(deletedCount) 个代理。"
            }
        }
        .alert("清空未锁定代理？", isPresented: $pendingClear) {
            Button("清空", role: .destructive) {
                do {
                    let deletedCount = try model.clearSocksProxies()
                    statusMessage = "已删除 \(deletedCount) 个未锁定代理。"
                } catch {
                    model.present(error)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除当前保存的 \(unlockedProxyCount) 个未锁定代理。锁定代理会保留；环境仍保留已选择的显示编号。")
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
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button(
                            ranking.proxy.isLocked ? "解锁" : "锁定",
                            systemImage: ranking.proxy.isLocked ? "lock.open" : "lock"
                        ) {
                            toggleLock(for: ranking.proxy)
                        }
                        .tint(ranking.proxy.isLocked ? .gray : .orange)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !ranking.proxy.isLocked {
                            Button("删除", systemImage: "trash", role: .destructive) {
                                pendingDelete = ranking.proxy
                            }
                        }
                        Button("测试", systemImage: "bolt.horizontal") {
                            validateProxy(ranking.proxy)
                        }
                        .tint(.green)
                        .disabled(isValidating)
                        Button("编辑", systemImage: "pencil") {
                            editorMode = .edit(ranking.proxy)
                        }
                        .tint(.indigo)
                    }
                    .contextMenu {
                        Button(
                            ranking.proxy.isLocked ? "取消锁定" : "锁定代理",
                            systemImage: ranking.proxy.isLocked ? "lock.open" : "lock"
                        ) {
                            toggleLock(for: ranking.proxy)
                        }
                        Button("测试代理", systemImage: "bolt.horizontal") {
                            validateProxy(ranking.proxy)
                        }
                        .disabled(isValidating)
                        Button("编辑代理", systemImage: "pencil") {
                            editorMode = .edit(ranking.proxy)
                        }
                        Button("复制代理", systemImage: "doc.on.doc") {
                            editorMode = .copy(ranking.proxy)
                        }
                        if !ranking.proxy.isLocked {
                            Button("删除代理", systemImage: "trash", role: .destructive) {
                                pendingDelete = ranking.proxy
                            }
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text("代理列表")
                Spacer()
                Text(validationSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
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
            Text(validationFooter)
        }
    }

    private var rankedProxies: [SocksProxyRanking] {
        model.rankedSocksProxies
    }

    private var unlockedProxyCount: Int {
        model.socksProxies.reduce(into: 0) { count, proxy in
            if !proxy.isLocked { count += 1 }
        }
    }

    private var validationSummary: String {
        let settings = model.socksProxyValidationSettings
        let retention = settings.retainOnlyAvailable ? "仅保留可用" : "保留全部"
        let count = settings.maxRetainedCount == 0 ? "不限数量" : "最多 \(settings.maxRetainedCount) 个"
        return "\(retention) · \(count) · \(settings.sortMode.title)"
    }

    private var validationFooter: String {
        let settings = model.socksProxyValidationSettings
        let target = settings.targetURLString
        let probe = settings.verifiesTLS ? "SOCKS CONNECT 和 HTTPS/TLS" : "SOCKS CONNECT"
        let retention = settings.retainOnlyAvailable ? "只保留可用代理" : "保留全部测试结果"
        let count = settings.maxRetainedCount == 0 ? "不限数量" : "最多保留 \(settings.maxRetainedCount) 个"
        return "预设链接只会在你点击“拉取”时访问网络，可保存多个来源。批量验证会测试 \(target) 的 \(probe)，\(retention)，\(count)；锁定代理始终保留。"
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
        testingProxyID = nil
        Task { @MainActor in
            defer {
                isValidating = false
                testingProxyID = nil
            }
            do {
                try await model.validateSocksProxies()
                let settings = model.socksProxyValidationSettings
                let count = settings.maxRetainedCount == 0
                    ? "不限数量"
                    : "最多 \(settings.maxRetainedCount) 个"
                let availability = settings.retainOnlyAvailable ? "仅保留可用代理" : "保留全部测试结果"
                statusMessage = "批量测试完成：\(availability)，\(count)，\(settings.sortMode.title)。"
            } catch {
                model.present(error)
            }
        }
    }

    private func validateProxy(_ proxy: SocksProxy) {
        guard !isValidating else { return }
        isValidating = true
        testingProxyID = proxy.id
        Task { @MainActor in
            defer {
                isValidating = false
                testingProxyID = nil
            }
            do {
                try await model.validateSocksProxy(proxy)
                statusMessage = "单独测试完成。"
            } catch {
                model.present(error)
            }
        }
    }

    private func toggleLock(for proxy: SocksProxy) {
        do {
            try model.setSocksProxyLocked(!proxy.isLocked, for: proxy)
        } catch {
            model.present(error)
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
                    if let code = ranking.proxy.displayCode {
                        Text(code)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        Text(ranking.proxy.displayAddress)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(ranking.proxy.displayAddress)
                            .font(.body.monospaced())
                            .lineLimit(1)
                    }
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
                if ranking.proxy.isLocked {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("已锁定")
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("第 \(ranking.number) 号，\(accessibilityName)，\(statusText)\(lockStatusText)")
    }

    private var accessibilityName: String {
        guard let code = ranking.proxy.displayCode else {
            return ranking.proxy.displayAddress
        }
        return "代号 \(code)，\(ranking.proxy.displayAddress)"
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

    private var lockStatusText: String {
        ranking.proxy.isLocked ? "，已锁定" : ""
    }
}

@MainActor
private struct SocksProxyBatchDeleteView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let onDeleted: (Int) -> Void

    @State private var selectedIDs = Set<UUID>()
    @State private var showsConfirmation = false
    @State private var presentedError: PresentedError?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.rankedSocksProxies) { ranking in
                        if ranking.proxy.isLocked {
                            SocksProxyBatchSelectionRow(
                                ranking: ranking,
                                isSelected: false
                            )
                        } else {
                            Button {
                                toggleSelection(ranking.proxy.id)
                            } label: {
                                SocksProxyBatchSelectionRow(
                                    ranking: ranking,
                                    isSelected: selectedIDs.contains(ranking.proxy.id)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } footer: {
                    Text("锁定代理不会被选中或删除。")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("批量删除")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("删除 \(selectedIDs.count) 个", systemImage: "trash", role: .destructive) {
                        showsConfirmation = true
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            }
            .alert("删除选中的代理？", isPresented: $showsConfirmation) {
                Button("删除", role: .destructive) {
                    deleteSelected()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将永久删除选中的 \(selectedIDs.count) 个代理。环境仍保留已选择的显示编号。")
            }
            .alert(item: $presentedError) { error in
                Alert(
                    title: Text("删除失败"),
                    message: Text(error.message),
                    dismissButton: .default(Text("好"))
                )
            }
        }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func deleteSelected() {
        do {
            let deletedCount = try model.deleteSocksProxies(withIDs: selectedIDs)
            onDeleted(deletedCount)
            dismiss()
        } catch {
            presentedError = PresentedError(message: error.localizedDescription)
        }
    }
}

private struct SocksProxyBatchSelectionRow: View {
    let ranking: SocksProxyRanking
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("\(ranking.number)")
                .font(.headline.monospacedDigit().weight(.bold))
                .foregroundStyle(.primary)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(ranking.proxy.displayCode ?? ranking.proxy.displayAddress)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if ranking.proxy.displayCode != nil {
                    Text(ranking.proxy.displayAddress)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if ranking.proxy.isLocked {
                Label("已锁定", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .accessibilityLabel(isSelected ? "已选择" : "未选择")
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let name = ranking.proxy.displayCode ?? ranking.proxy.displayAddress
        if ranking.proxy.isLocked {
            return "第 \(ranking.number) 号，\(name)，已锁定，不能删除"
        }
        return "第 \(ranking.number) 号，\(name)，\(isSelected ? "已选择" : "未选择")"
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
    case copy(SocksProxy)

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let proxy): proxy.id.uuidString
        case .copy(let proxy): "copy-\(proxy.id.uuidString)"
        }
    }

    var proxy: SocksProxy? {
        switch self {
        case .create: nil
        case .edit(let proxy), .copy(let proxy): proxy
        }
    }

    var isCopy: Bool {
        if case .copy = self { return true }
        return false
    }

    var createsNewRecord: Bool {
        switch self {
        case .create, .copy: true
        case .edit: false
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
