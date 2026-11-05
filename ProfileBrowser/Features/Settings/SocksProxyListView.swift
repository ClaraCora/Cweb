import SwiftUI

@MainActor
struct SocksProxyListView: View {
    @Environment(AppModel.self) private var model

    @State private var editorMode: SocksProxyEditorMode?
    @State private var showsImport = false
    @State private var importReport: ProxyImportReport?
    @State private var showsPresets = false
    @State private var showsBatchDelete = false
    @State private var showsExport = false
    @State private var presetsExpanded = false
    @State private var showsCleanup = false
    @State private var pendingClear = false
    @State private var pendingDelete: SocksProxy?
    @State private var activity: ProxyActivity?
    @State private var statusMessage: String?
    @State private var statusIsWarning = false
    @State private var completedCount = 0
    @State private var totalCount = 0
    @State private var searchText = ""

    var body: some View {
        @Bindable var model = model

        List {
            Section {
                proxySummary
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }
            .disabled(isValidating)
            if let activity {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        if case .batchValidation = activity {
                            HStack {
                                Text(activity.title)
                                Spacer(minLength: 8)
                                Text("\(completedCount) / \(totalCount)")
                                    .monospacedDigit()
                                    .foregroundStyle(AppUI.secondaryText)
                            }
                            ProgressView(value: Double(completedCount), total: Double(max(1, totalCount)))
                        } else {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text(activity.title)
                            }
                        }
                    }
                    .font(.subheadline)
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .combine)
                }
            } else if let statusMessage {
                Section {
                    HStack(spacing: 8) {
                        AppStatusMessage(message: statusMessage, tone: statusIsWarning ? .warning : .success)
                            .accessibilityIdentifier("proxy.result")
                        Spacer(minLength: 0)
                        Button("关闭结果", systemImage: "xmark") {
                            self.statusMessage = nil
                        }
                        .labelStyle(.iconOnly)
                        .font(.footnote)
                        .frame(minWidth: 44, minHeight: 44)
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("proxy.dismissResult")
                    }
                }
            }
            proxySection
                .disabled(isValidating)
            presetSection
                .disabled(isValidating)
        }
        .listStyle(.plain)
        .listSectionSpacing(0)
        .scrollDismissesKeyboard(.interactively)
        .environment(\.defaultMinListRowHeight, 44)
        .readableListMargins(minimum: 0)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "编号、代号或地址")
        .navigationTitle("代理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("测速", systemImage: "bolt.horizontal") {
                    validateProxies()
                }
                .labelStyle(.titleOnly)
                .disabled(model.socksProxies.isEmpty || isValidating)
                .accessibilityIdentifier("proxy.validateAll")

                Menu {
                    Button("导入代理", systemImage: "link.badge.plus") { showsImport = true }
                    Button("添加代理", systemImage: "plus") { editorMode = .create }
                    Button("批量导出", systemImage: "square.and.arrow.up") { showsExport = true }
                        .disabled(model.socksProxies.isEmpty)
                    Divider()
                    Button("管理预设链接", systemImage: "list.bullet.rectangle") {
                        showsPresets = true
                    }
                    NavigationLink {
                        SocksProxySettingsView(settings: model.socksProxyValidationSettings)
                    } label: {
                        Label("测速与保留规则", systemImage: "slider.horizontal.3")
                    }
                    Divider()
                    Button("预览规则清理", systemImage: "line.3.horizontal.decrease") { showsCleanup = true }
                        .disabled(model.proxyCleanupIDs.isEmpty)
                    if model.canUndoProxyDeletion {
                        Button("撤销最近删除", systemImage: "arrow.uturn.backward") {
                            do { try model.undoProxyDeletion() } catch { model.present(error) }
                        }
                    }
                    Button("批量删除", systemImage: "checklist") {
                        showsBatchDelete = true
                    }
                    .disabled(unlockedProxyCount == 0 || isValidating)
                    Button("清空未锁定代理", systemImage: "trash", role: .destructive) {
                        pendingClear = true
                    }
                    .disabled(unlockedProxyCount == 0 || isValidating)
                } label: {
                    Label("更多代理操作", systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                }
                .disabled(isValidating)
                .accessibilityIdentifier("proxy.more")
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
            SocksProxyImportView()
        }
        .sheet(item: $importReport) { report in
            ProxyImportReportView(report: report)
        }
        .sheet(isPresented: $showsPresets) {
            SocksProxyPresetListView()
        }
        .sheet(isPresented: $showsExport) {
            SocksProxyExportView(rankings: model.rankedSocksProxies)
        }
        .sheet(isPresented: $showsCleanup) { ProxyCleanupView() }
        .sheet(isPresented: $showsBatchDelete) {
            SocksProxyBatchDeleteView { deletedCount in
                statusIsWarning = false
                statusMessage = "已删除 \(deletedCount) 个代理。"
            }
        }
        .alert("清空未锁定代理？", isPresented: $pendingClear) {
            Button("清空", role: .destructive) {
                do {
                    let deletedCount = try model.clearSocksProxies()
                    statusIsWarning = false
                    statusMessage = "已删除 \(deletedCount) 个未锁定代理。"
                } catch {
                    model.present(error)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除 \(unlockedProxyCount) 个未锁定代理。" + model.proxyDeletionImpact(for: Set(model.socksProxies.filter { !$0.isLocked }.map(\.id))))
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
            Text("将删除 \(proxy.displayAddress)。" + model.proxyDeletionImpact(for: [proxy.id]))
        }
        .alert(item: $model.presentedError) { error in
            Alert(
                title: Text("操作失败"),
                message: Text(error.message),
                dismissButton: .default(Text("好"))
            )
        }
    }

    private var proxySummary: some View {
        NavigationLink {
            SocksProxySettingsView(settings: model.socksProxyValidationSettings)
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    proxyCount
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 8)
                    validationMethod
                        .fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 4) {
                    proxyCount
                    validationMethod
                }
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .accessibilityLabel("共 \(model.socksProxies.count) 条代理，\(model.socksProxies.filter(\.isAvailable).count) 条可用，测速与保留规则")
        .accessibilityHint("查看或修改测速方式和结果保留规则")
    }

    private var proxyCount: some View {
        Text(searchText.isEmpty
             ? "共 \(model.socksProxies.count) 条 · \(model.socksProxies.filter(\.isAvailable).count) 可用"
             : "匹配 \(rankedProxies.count) / \(model.socksProxies.count) 条")
            .foregroundStyle(AppUI.secondaryText)
            .monospacedDigit()
    }

    private var validationMethod: some View {
        Text(model.socksProxyValidationSettings.verifiesTLS ? "TLS 握手" : "SOCKS 连接")
            .foregroundStyle(Color.accentColor)
    }

    @ViewBuilder
    private var proxySection: some View {
        Section {
            if model.socksProxies.isEmpty {
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
            } else if rankedProxies.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ForEach(rankedProxies) { ranking in
                    SocksProxyRow(ranking: ranking, isTesting: activity?.proxyID == ranking.proxy.id) {
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
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    @ViewBuilder
    private var presetSection: some View {
        Section {
            DisclosureGroup("预设链接（\(model.proxyPresets.count)）", isExpanded: $presetsExpanded) {
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
                                    .foregroundStyle(AppUI.secondaryText)
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
                Button("管理预设链接", systemImage: "slider.horizontal.3") { showsPresets = true }
            }
            .font(.subheadline)
        }
    }

    private var rankedProxies: [SocksProxyRanking] {
        model.rankedSocksProxies.filter { ranking in
            searchText.isEmpty || "\(ranking.number) \(ranking.proxy.displayCode ?? "") \(ranking.proxy.displayAddress)"
                .localizedCaseInsensitiveContains(searchText)
        }
    }

    private var unlockedProxyCount: Int {
        model.socksProxies.reduce(into: 0) { count, proxy in
            if !proxy.isLocked { count += 1 }
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    private var isValidating: Bool { activity != nil }

    private func validateProxies() {
        guard !isValidating else { return }
        activity = .batchValidation
        statusMessage = nil
        completedCount = 0
        totalCount = model.socksProxies.count
        Task { @MainActor in
            defer { activity = nil }
            do {
                try await model.validateSocksProxies { completed, total in
                    completedCount = completed
                    totalCount = total
                }
                statusIsWarning = false
                statusMessage = "测速完成，共 \(model.socksProxies.count) 个代理。"
            } catch {
                model.present(error)
            }
        }
    }

    private func validateProxy(_ proxy: SocksProxy) {
        guard !isValidating else { return }
        activity = .singleValidation(proxy.id, proxy.displayCode ?? proxy.displayAddress)
        statusMessage = nil
        Task { @MainActor in
            defer { activity = nil }
            do {
                try await model.validateSocksProxy(proxy)
                if let result = model.socksProxies.first(where: { $0.id == proxy.id }) {
                    statusIsWarning = result.status != .available
                    statusMessage = result.status == .available
                        ? "\(result.displayCode ?? result.displayAddress)：可用，\(result.latencyMilliseconds ?? 0) ms。"
                        : "\(result.displayCode ?? result.displayAddress)：\(result.validationMessage ?? "无法连接")"
                }
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
        activity = .importing(preset.displayName)
        statusMessage = nil
        Task { @MainActor in
            defer { activity = nil }
            do {
                let report = try await model.importSocksProxies(from: preset.url)
                statusIsWarning = false
                statusMessage = "\(preset.displayName)：\(report.summary)"
                importReport = report
            } catch {
                model.present(error)
            }
        }
    }
}

private enum ProxyActivity {
    case batchValidation
    case singleValidation(UUID, String)
    case importing(String)

    var title: String {
        switch self {
        case .batchValidation: "正在批量测速"
        case .singleValidation(_, let name): "正在测试 \(name)"
        case .importing(let name): "正在拉取 \(name)"
        }
    }

    var proxyID: UUID? {
        if case .singleValidation(let id, _) = self { return id }
        return nil
    }
}

private struct SocksProxyRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let ranking: SocksProxyRanking
    let isTesting: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Text("\(ranking.number)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppUI.secondaryText)
                    .frame(minWidth: 24, alignment: .leading)
                    .padding(.top, 2)

                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        identity
                        validationResult
                    }
                } else {
                    identity
                    Spacer(minLength: 8)
                    validationResult
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(ListRowButtonStyle())
        .accessibilityIdentifier("proxy.row.\(ranking.number)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(ranking.number) 号，\(accessibilityName)，\(statusText)\(lockStatusText)")
        .accessibilityValue(accessibilityResult)
        .accessibilityHint("轻点编辑，侧滑或长按进行测试、锁定等操作")
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.tight) {
            HStack(spacing: 6) {
                Text(ranking.proxy.displayCode ?? endpoint)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                if ranking.proxy.isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(AppUI.secondaryText)
                        .accessibilityHidden(true)
                }
            }
            Text(ranking.proxy.displayCode == nil ? ranking.proxy.scheme.rawValue.uppercased() : endpoint)
                .font(.caption)
                .foregroundStyle(AppUI.secondaryText)
        }
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var endpoint: String {
        let host = SocksProxy.normalizeHost(ranking.proxy.host)
        return "\(host.contains(":") ? "[\(host)]" : host):\(ranking.proxy.port)"
    }

    private var validationResult: some View {
        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: AppUI.Spacing.tight) {
            if isTesting {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("测速中")
                        .font(.caption)
                        .foregroundStyle(AppUI.secondaryText)
                }
            } else {
                switch ranking.proxy.latestStatus {
                case .available:
                    if let latency = ranking.proxy.latestLatency {
                        Text("\(latency) ms")
                            .font(.subheadline.weight(.medium).monospacedDigit())
                            .foregroundStyle(AppUI.latencyColor(latency))
                    }
                    resultMetadata("可用", icon: "checkmark.circle")
                case .unavailable:
                    Text("不可用")
                        .font(.subheadline)
                        .foregroundStyle(AppUI.danger)
                    resultMetadata("连接失败", icon: "exclamationmark.circle")
                case .untested:
                    Text("未测速")
                        .font(.subheadline)
                        .foregroundStyle(AppUI.secondaryText)
                }
            }
        }
    }

    private func resultMetadata(_ title: String, icon: String) -> some View {
        HStack(spacing: AppUI.Spacing.tight) {
            Image(systemName: icon).accessibilityHidden(true)
            Text(title + checkedAtSuffix)
        }
        .font(.caption)
        .foregroundStyle(AppUI.secondaryText)
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
    }

    private var checkedAtSuffix: String {
        guard let date = ranking.proxy.latestMeasurement?.checkedAt else { return "" }
        let display = Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .shortened)
        return " · " + display
    }

    private var accessibilityResult: String {
        if isTesting { return "正在测速" }
        if let latency = ranking.proxy.latestLatency, ranking.proxy.isAvailable {
            return "延迟 \(latency) 毫秒"
        }
        return ranking.proxy.latestMeasurement?.message ?? ""
    }

    private var accessibilityName: String {
        guard let code = ranking.proxy.displayCode else {
            return ranking.proxy.displayAddress
        }
        return "代号 \(code)，\(ranking.proxy.displayAddress)"
    }

    private var statusText: String {
        switch ranking.proxy.latestStatus {
        case .available: "可用"
        case .unavailable: "不可用"
        case .untested: "未测速"
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
                    Button(selectedIDs == selectableIDs ? "取消全选" : "全选未锁定代理") {
                        selectedIDs = selectedIDs == selectableIDs ? [] : selectableIDs
                    }
                    .disabled(selectableIDs.isEmpty)
                    .accessibilityIdentifier("proxy.selectAll")
                    LabeledContent("已选择", value: "\(selectedIDs.count) 个")
                }
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
                    Button("删除", role: .destructive) {
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
                Text("将删除选中的 \(selectedIDs.count) 个代理。" + model.proxyDeletionImpact(for: selectedIDs))
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

    private var selectableIDs: Set<UUID> {
        Set(model.socksProxies.filter { !$0.isLocked }.map(\.id))
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
                        .foregroundStyle(AppUI.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if ranking.proxy.isLocked {
                Label("已锁定", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(AppUI.secondaryText)
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
                                        .foregroundStyle(AppUI.secondaryText)
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
