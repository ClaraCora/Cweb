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
    @State private var statusFilter: ProxyStatusFilter = .all
    @State private var showsRules = false

    var body: some View {
        @Bindable var model = model
        let visible = rankedProxies
        let counts = model.socksProxies.reduce(into: [SocksProxyStatus: Int]()) {
            $0[$1.latestStatus, default: 0] += 1
        }

        List {
            Section {
                proxySummary(availableCount: counts[.available, default: 0], visibleCount: visible.count)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 16, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
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
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 16, trailing: 20))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
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
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 16, trailing: 20))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            if !model.socksProxies.isEmpty {
                Section {
                    proxyFilters(counts: counts)
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 12, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            proxySection(visibleProxies: visible)
                .disabled(isValidating)
            presetSection
                .disabled(isValidating)
        }
        .listStyle(.plain)
        .listSectionSpacing(0)
        .scrollContentBackground(.hidden)
        .background { WorkspaceBackdrop() }
        .scrollDismissesKeyboard(.interactively)
        .environment(\.defaultMinListRowHeight, 44)
        .accessibilityIdentifier("proxy.list")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "编号、代号或地址")
        .navigationTitle("代理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    editorMode = .create
                } label: {
                    Image(systemName: "plus")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("添加代理")
                .disabled(isValidating)
                .accessibilityIdentifier("proxy.add")

                Menu {
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
                        .frame(minWidth: 44, minHeight: 44)
                }
                .disabled(isValidating)
                .accessibilityIdentifier("proxy.more")
            }
        }
        .navigationDestination(isPresented: $showsRules) {
            SocksProxySettingsView(settings: model.socksProxyValidationSettings)
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

    private func proxySummary(availableCount: Int, visibleCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "network")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 48, height: 48)
                    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("代理管理")
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(searchText.isEmpty
                         ? "共 \(model.socksProxies.count) 条 · \(availableCount) 条可用"
                         : "匹配 \(visibleCount) / \(model.socksProxies.count) 条")
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(AppUI.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    showsRules = true
                } label: {
                    VStack(alignment: .trailing, spacing: 4) {
                        Label("测速规则", systemImage: "slider.horizontal.3")
                            .font(.subheadline.weight(.medium))
                        Text(model.socksProxyValidationSettings.verifiesTLS ? "TLS 握手" : "SOCKS 连接")
                            .font(.caption)
                            .foregroundStyle(AppUI.secondaryText)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .layoutPriority(1)
                .foregroundStyle(Color.accentColor)
                .accessibilityHint("查看或修改测速方式和结果保留规则")
                .accessibilityIdentifier("proxy.rules")
            }

            HStack(spacing: 8) {
                Button {
                    validateProxies()
                } label: {
                    Label("批量测速", systemImage: "bolt.horizontal.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(Color(.systemBackground))
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(model.socksProxies.isEmpty || isValidating)
                .opacity(model.socksProxies.isEmpty || isValidating ? 0.45 : 1)
                .accessibilityIdentifier("proxy.validateAll")

                Button {
                    showsImport = true
                } label: {
                    Label("导入代理", systemImage: "arrow.down.to.line")
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(Color.accentColor)
                        .background(Color(.quaternarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isValidating)
                .opacity(isValidating ? 0.45 : 1)
                .accessibilityIdentifier("proxy.import")
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.plain)
        }
        .padding(16)
        .beamPanel(cornerRadius: 18, active: true)
    }

    private func proxyFilters(counts: [SocksProxyStatus: Int]) -> some View {
        HStack(spacing: 2) {
            ForEach(ProxyStatusFilter.allCases) { filter in
                let isSelected = statusFilter == filter
                let count = filter.status.map { counts[$0, default: 0] } ?? model.socksProxies.count
                Button {
                    statusFilter = filter
                } label: {
                    VStack(spacing: 2) {
                        Text(count, format: .number)
                            .font(.headline.monospacedDigit())
                        Text(filter.title)
                            .font(.caption.weight(isSelected ? .semibold : .regular))
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(isSelected ? Color.accentColor : AppUI.secondaryText)
                    .background(isSelected ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(filter.title)，\(count) 条")
                .accessibilityValue(isSelected ? "已选择" : "未选择")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("proxy.filter." + filter.rawValue)
            }
        }
        .padding(4)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .disabled(isValidating)
    }

    @ViewBuilder
    private func proxySection(visibleProxies: [SocksProxyRanking]) -> some View {
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
            } else if visibleProxies.isEmpty {
                if !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ContentUnavailableView {
                        Label("暂无\(statusFilter.title)代理", systemImage: "network")
                    } actions: {
                        Button("查看全部代理") { statusFilter = .all }
                            .buttonStyle(.bordered)
                    }
                }
            } else {
                ForEach(visibleProxies) { ranking in
                    SocksProxyRow(ranking: ranking, isTesting: activity?.proxyID == ranking.proxy.id) {
                        editorMode = .edit(ranking.proxy)
                    }
                    .background {
                        UnevenRoundedRectangle(
                            topLeadingRadius: ranking.id == visibleProxies.first?.id ? 16 : 0,
                            bottomLeadingRadius: ranking.id == visibleProxies.last?.id ? 16 : 0,
                            bottomTrailingRadius: ranking.id == visibleProxies.last?.id ? 16 : 0,
                            topTrailingRadius: ranking.id == visibleProxies.first?.id ? 16 : 0
                        )
                        .fill(Color(.secondarySystemGroupedBackground))
                    }
                    .overlay(alignment: .bottom) {
                        if ranking.id != visibleProxies.last?.id {
                            Divider().padding(.leading, 64).padding(.trailing, 16)
                        }
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
                        if let measurement = ranking.proxy.latestMeasurement {
                            Label("测速于 \(measurement.checkedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
                        }
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
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var presetSection: some View {
        Section {
            DisclosureGroup(isExpanded: $presetsExpanded) {
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
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "link")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.indigo)
                        .frame(width: 36, height: 36)
                        .background(Color.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("预设链接")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("从常用订阅快速拉取")
                            .font(.footnote)
                            .foregroundStyle(AppUI.secondaryText)
                    }
                    Spacer(minLength: 8)
                    Text("\(model.proxyPresets.count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(AppUI.secondaryText)
                }
                .frame(minHeight: 44)
            }
            .font(.subheadline)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .accessibilityIdentifier("proxy.presets")
        }
        .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 20, trailing: 20))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var rankedProxies: [SocksProxyRanking] {
        let rankings = model.rankedSocksProxies
        guard statusFilter != .all || !searchText.isEmpty else { return rankings }
        return rankings.filter { ranking in
            statusFilter.includes(ranking.proxy) && (searchText.isEmpty || "\(ranking.number) \(ranking.proxy.displayCode ?? "") \(ranking.proxy.displayAddress)"
                .localizedCaseInsensitiveContains(searchText))
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

private enum ProxyStatusFilter: String, CaseIterable, Identifiable {
    case all, available, untested, unavailable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .available: "可用"
        case .untested: "未测速"
        case .unavailable: "不可用"
        }
    }

    var status: SocksProxyStatus? {
        switch self {
        case .all: nil
        case .available: .available
        case .untested: .untested
        case .unavailable: .unavailable
        }
    }

    func includes(_ proxy: SocksProxy) -> Bool {
        status.map { proxy.latestStatus == $0 } ?? true
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
            HStack(spacing: 12) {
                Text("\(ranking.number)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.accentColor)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

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
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("proxy.row.\(ranking.number)")
        .accessibilityLabel("第 \(ranking.number) 号，\(accessibilityName)，\(statusText)\(lockStatusText)")
        .accessibilityValue(accessibilityResult)
        .accessibilityHint("轻点编辑，侧滑或长按进行测试、锁定等操作")
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.tight) {
            HStack(spacing: 6) {
                Text(ranking.proxy.displayCode ?? endpoint)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                if ranking.proxy.isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(AppUI.secondaryText)
                        .accessibilityHidden(true)
                }
            }
            Text(ranking.proxy.displayCode == nil ? ranking.proxy.scheme.rawValue.uppercased() : endpoint)
                .font(.footnote)
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
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppUI.latencyColor(latency).opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }
                    resultMetadata("可用", icon: "checkmark.circle")
                case .unavailable:
                    Text("不可用")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppUI.danger)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppUI.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    resultMetadata("连接失败", icon: "exclamationmark.circle")
                case .untested:
                    Text("未测速")
                        .font(.subheadline)
                        .foregroundStyle(AppUI.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func resultMetadata(_ title: String, icon: String) -> some View {
        HStack(spacing: AppUI.Spacing.tight) {
            Image(systemName: icon).accessibilityHidden(true)
            Text(title)
        }
        .font(.caption)
        .foregroundStyle(AppUI.secondaryText)
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
    }

    private var checkedAtDescription: String {
        guard let date = ranking.proxy.latestMeasurement?.checkedAt else { return "" }
        let display = Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .shortened)
        return "，测速于 " + display
    }

    private var accessibilityResult: String {
        if isTesting { return "正在测速" }
        if let latency = ranking.proxy.latestLatency, ranking.proxy.isAvailable {
            return "延迟 \(latency) 毫秒" + checkedAtDescription
        }
        return (ranking.proxy.latestMeasurement?.message ?? "") + checkedAtDescription
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
