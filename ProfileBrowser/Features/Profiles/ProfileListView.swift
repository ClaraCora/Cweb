import SwiftUI

@MainActor
struct ProfileListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let groupID: UUID
    let onDeleteGroup: ((UUID) -> Void)?

    @State private var searchText = ""
    @State private var todayFilter = 0
    @State private var editorMode: ProfileEditorMode?
    @State private var groupEditor: ProfileGroup?
    @State private var pendingGroupDeletion: ProfileGroup?
    @State private var pendingDeletion: BrowserProfile?
    @State private var pendingClear: BrowserProfile?
    @State private var pendingEntry: BrowserProfile?
    @State private var ipDetectionProfile: BrowserProfile?
    @State private var activeProfile: BrowserProfile?
    @State private var showsGroupCheckIn = false
    @State private var checkInController: GroupCheckInController?
    @State private var editMode: EditMode = .inactive
    @State private var isTestingProxies = false
    @State private var testingProxyIDs: Set<UUID> = []
    @State private var proxyTestCompleted = 0
    @State private var proxyTestTotal = 0
    @State private var proxyTestSummary: String?

    init(groupID: UUID, onDeleteGroup: ((UUID) -> Void)? = nil) {
        self.groupID = groupID
        self.onDeleteGroup = onDeleteGroup
    }

    var body: some View {
        confirmationContent
            .safeAreaInset(edge: .top, spacing: 0) {
                if !groupProfiles.isEmpty { checkInControls }
            }
            .environment(\.editMode, $editMode)
    }

    private var navigationContent: some View {
        content
            .navigationTitle(currentGroup?.name ?? "分组")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索环境名称、主页或代理")
            .onAppear(perform: restoreActiveGroupRun)
            .task(id: isTestingProxies) {
                if isTestingProxies { await measureGroupProxies() }
            }
            .navigationDestination(item: $activeProfile) { profile in
                BrowserView(profile: profile, socksProxy: model.socksProxy(for: profile))
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(editMode == .active ? "完成" : "排序") {
                        editMode = editMode == .active ? .inactive : .active
                    }
                    .disabled(!searchText.isEmpty || todayFilter != 0 || isGroupLocked)
                    .accessibilityIdentifier("profiles.reorder")
                    Button("新建", systemImage: "plus") {
                        editorMode = .create
                    }
                    Menu {
                        Picker("今日签到", selection: $todayFilter) {
                            Text("全部环境").tag(0); Text("今天待签到").tag(1); Text("今天已完成").tag(2)
                        }
                        if let currentGroup {
                            Button("编辑分组", systemImage: "pencil") { groupEditor = currentGroup }
                                .disabled(isGroupLocked)
                        }
                        Button("删除整个分组", systemImage: "trash", role: .destructive) {
                            if let currentGroup {
                                pendingGroupDeletion = currentGroup
                            }
                        }
                        .disabled(currentGroup == nil || isGroupLocked)
                    } label: {
                        Label("更多", systemImage: "ellipsis.circle")
                    }
                }
            }
    }

    private var presentedContent: some View {
        navigationContent
            .sheet(item: $editorMode) { mode in
                ProfileEditorView(
                    profile: mode.profile,
                    defaultGroupName: mode.profile == nil && currentGroup?.name != "未分组"
                        ? currentGroup?.name
                        : nil
                ) { submission in
                    switch submission {
                    case .create(let name, let groupName, let homePage, let userAgent, let color, let socksProxyNumber, let autofillUsername, let autofillPassword):
                        try model.addProfile(
                            name: name,
                            groupName: groupName,
                            homePage: homePage,
                            userAgent: userAgent,
                            color: color,
                            socksProxyNumber: socksProxyNumber,
                            autofillUsername: autofillUsername,
                            autofillPassword: autofillPassword
                        )
                    case .update(let profile, let autofillUsername, let autofillPassword):
                        try model.updateProfile(
                            profile,
                            autofillUsername: autofillUsername,
                            autofillPassword: autofillPassword
                        )
                    }
                }
            }
            .sheet(item: $groupEditor) { group in
                ProfileGroupEditorView(group: group) { name, code, emoji in
                    try model.updateGroup(
                        id: group.id,
                        name: name,
                        code: code,
                        emoji: emoji
                    )
                }
            }
            .sheet(item: $ipDetectionProfile) { profile in
                IPDetectionView(
                    profile: profile,
                    socksProxy: model.socksProxy(for: profile)
                )
            }
            .fullScreenCover(isPresented: $showsGroupCheckIn) {
                if let checkInController { GroupCheckInView(controller: checkInController) }
            }
    }

    private var deletionContent: some View {
        presentedContent
            .alert("删除整个分组？", isPresented: groupDeletionAlertBinding, presenting: pendingGroupDeletion) { group in
                Button("删除", role: .destructive) {
                    pendingGroupDeletion = nil
                    requestGroupDeletion(group.id)
                }
                Button("取消", role: .cancel) {}
            } message: { group in
                Text("将永久删除“\(group.name)”中的 \(group.profiles.count) 个环境和已保存凭据。旧环境的网站数据将被弃用，且不会被新环境复用。")
            }
            .alert("删除环境？", isPresented: deletionAlertBinding, presenting: pendingDeletion) { profile in
                Button("删除", role: .destructive) {
                    pendingDeletion = nil
                    if groupProfiles.count == 1,
                       model.profiles.contains(where: { $0.id == profile.id }) {
                        requestGroupDeletion(groupID)
                    } else {
                        Task { await model.deleteProfile(profile) }
                    }
                }
                Button("取消", role: .cancel) {}
            } message: { profile in
                Text("将永久删除“\(profile.name)”和已保存凭据。旧环境的网站数据将被弃用，且不会被新环境复用。")
            }
            .alert("清理网站数据？", isPresented: clearAlertBinding, presenting: pendingClear) { profile in
                Button("清理", role: .destructive) {
                    Task { await model.clearWebsiteData(for: profile) }
                }
                Button("取消", role: .cancel) {}
            } message: { profile in
                Text("将清除“\(profile.name)”的 Cookie、缓存和网站存储，但保留该环境和已保存凭据。")
            }
    }

    private var confirmationContent: some View {
        @Bindable var model = model

        return deletionContent
            .alert("进入环境？", isPresented: entryAlertBinding, presenting: pendingEntry) { profile in
                Button("进入") {
                    pendingEntry = nil
                    model.confirmEntry(for: profile)
                    activeProfile = profile
                }
                Button("取消", role: .cancel) {}
            } message: { profile in
                Text(entryConfirmationMessage(for: profile))
            }
            .alert(item: $model.presentedError) { error in
                Alert(
                    title: Text("操作失败"),
                    message: Text(error.message),
                    dismissButton: .default(Text("好"))
                )
            }
    }

    private func restoreActiveGroupRun() {
        guard let run = model.activeGroupRun, run.groupID == groupID else { return }
        checkInController = run
    }

    private var checkInControls: some View {
        VStack(alignment: .leading, spacing: 0) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 0) {
                    checkInSummary
                    checkInButtons
                }
            } else {
                HStack(spacing: 8) {
                    checkInSummary
                    checkInButtons
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            if isCheckInScriptEmpty {
                Text("签到脚本为空，请先在设置中恢复模板或填写脚本。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var checkInButtons: some View {
        GroupCheckInControls(
            canStart: canStartCheckIn,
            canPause: checkInController?.canPause == true,
            canStop: checkInController?.canStop == true,
            start: startCheckIn,
            pause: { checkInController?.pause() },
            stop: { checkInController?.stop() }
        )
    }

    @ViewBuilder
    private var checkInSummary: some View {
        if let checkInController, checkInController.canStop {
            Button {
                showsGroupCheckIn = true
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(checkInController.queue.index + 1)/\(checkInController.queue.profileIDs.count) · \(checkInController.isPaused ? "已暂停" : "签到中")")
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                    Text("返回签到页面")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回签到页面，第 \(checkInController.queue.index + 1) 个，共 \(checkInController.queue.profileIDs.count) 个，已完成 \(checkInController.queue.completedCount) 个")
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.pendingGroupRun?.groupID == groupID ? "恢复上次任务" : "分组签到")
                    .font(.subheadline.weight(.medium))
                Text("\(groupProfiles.count) 个环境 · 按序执行")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .accessibilityHint("今天已完成签到的环境会自动跳过")
        }
    }

    private var canStartCheckIn: Bool {
        editMode != .active && !groupProfiles.isEmpty && !isTestingProxies
            && !isCheckInScriptEmpty
            && (checkInController?.canStop != true || checkInController?.canStart == true)
    }

    private var isCheckInScriptEmpty: Bool {
        model.globalScriptSettings.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func startCheckIn() {
        if checkInController?.canStop != true {
            guard let group = currentGroup else { return }
            checkInController = model.groupRun(for: group)
        }
        checkInController?.start()
        showsGroupCheckIn = checkInController?.hasStarted == true
    }

    @ViewBuilder
    private var content: some View {
        if visibleProfiles.isEmpty && !groupProfiles.isEmpty {
            ContentUnavailableView("没有符合条件的环境", systemImage: "line.3.horizontal.decrease", description: Text("调整搜索内容或今日签到筛选后重试。"))
        } else if visibleProfiles.isEmpty {
            ContentUnavailableView {
                Label("这个分组还没有环境", systemImage: "person.crop.square")
            } actions: {
                Button("新建环境", systemImage: "plus") {
                    editorMode = .create
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            List {
                Section {
                    ForEach(visibleProfiles) { profile in
                        profileButton(for: profile)
                    }
                    .onMove { offsets, destination in
                        do {
                            try model.moveProfiles(
                                visibleProfiles.map(\.id),
                                fromOffsets: offsets,
                                toOffset: destination
                            )
                        } catch {
                            model.present(error)
                        }
                    }
                } header: {
                    groupProxyHeader
                } footer: {
                    if let proxyTestSummary { Text(proxyTestSummary) }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var groupProxyHeader: some View {
        HStack(spacing: 8) {
            Text("\(visibleProfiles.count) 个环境")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button {
                isTestingProxies = true
            } label: {
                HStack(spacing: 6) {
                    if isTestingProxies { ProgressView().controlSize(.small) }
                    Text(isTestingProxies ? "测速 \(proxyTestCompleted)/\(proxyTestTotal)" : "批量测速")
                        .font(.subheadline)
                        .monospacedDigit()
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.borderless)
            .disabled(isTestingProxies || editMode == .active || checkInController?.canStop == true
                || model.groupProxyTargets(for: visibleProfiles).isEmpty)
            .accessibilityHint("仅测本组使用的代理，共用代理只测一次，直连环境不参与")
            .accessibilityIdentifier("profiles.testProxies")
        }
        .textCase(nil)
    }

    private func measureGroupProxies() async {
        let profiles = visibleProfiles
        let targets = model.groupProxyTargets(for: profiles)
        testingProxyIDs = Set(targets.map(\.id))
        proxyTestCompleted = 0
        proxyTestTotal = targets.count
        proxyTestSummary = nil
        defer {
            isTestingProxies = false
            testingProxyIDs = []
        }
        do {
            let results = try await model.validateGroupProxyLatencies(for: profiles) { completed, total in
                proxyTestCompleted = completed
                proxyTestTotal = total
            }
            let available = results.filter { $0.status == .available }.count
            proxyTestSummary = results.isEmpty
                ? "代理或测速规则已变化，请重新测速。"
                : "已测 \(results.count) 个代理 · 可用 \(available) · 不可用 \(results.count - available)"
        } catch is CancellationError {
            proxyTestSummary = nil
        } catch {
            proxyTestSummary = "测速结果未保存，请重试。"
            model.present(error)
        }
    }

    private var isGroupLocked: Bool { !model.reservedProfileIDs.isDisjoint(with: Set(groupProfiles.map(\.id))) }

    private var visibleProfiles: [BrowserProfile] {
        groupProfiles.filter { profile in
            let pending = model.shouldRunAutomation(for: profile.id)
            let matches = searchText.isEmpty || (profile.name + " " + profile.homePageHost + " " + proxySummary(for: profile))
                .localizedStandardContains(searchText)
            return matches && (todayFilter == 0 || (todayFilter == 1 ? pending : !pending))
        }
    }

    private var groupProfiles: [BrowserProfile] {
        model.sortedProfiles.filter { profile in
            if let profileGroupID = profile.groupID {
                return profileGroupID == groupID
            }
            return profile.displayGroupName == currentGroup?.name
        }
    }

    private var currentGroup: ProfileGroup? {
        model.profileGroups.first { $0.id == groupID }
    }

    private func entryConfirmationMessage(for profile: BrowserProfile) -> String {
        let environment = "将使用“\(profile.name)”的独立网站数据和 User-Agent 打开主页。"
        if profile.unresolvedProxyNumber != nil {
            return "此环境需要重新选择代理。请先编辑环境，明确选择代理或不使用代理；处理前不会联网。"
        }
        guard let proxyNumber = profile.socksProxyNumber else {
            return "\(environment)\n\n代理：未选择，将使用设备当前网络。"
        }
        guard let proxy = model.socksProxy(for: profile) else {
            return "\(environment)\n\n代理：已选择第 \(proxyNumber) 号，但该编号当前不存在；进入后不会改用直连。"
        }

        let name = proxy.displayCode.map { "\($0) · " } ?? ""
        return "\(environment)\n\n代理：第 \(proxyNumber) 号 · \(name)\(proxy.displayAddress)。"
    }

    private func profileButton(for profile: BrowserProfile) -> some View {
        Button {
            guard editMode != .active else { return }
            guard !model.reservedProfileIDs.contains(profile.id) else {
                model.present(ProfileError.taskInProgress); return
            }
            if profile.unresolvedProxyNumber != nil || (profile.socksProxyNumber != nil && model.socksProxy(for: profile) == nil) {
                editorMode = .edit(profile)
            } else if model.needsEntryConfirmation(for: profile) { pendingEntry = profile }
            else { activeProfile = profile }
        } label: {
            ProfileRow(
                profile: profile,
                balance: model.balance(for: profile),
                balanceStatus: model.balanceStatus(for: profile),
                todayCompleted: !model.shouldRunAutomation(for: profile.id),
                proxyMeasuredAt: model.socksProxy(for: profile)?.latestMeasurement?.checkedAt,
                proxySummary: proxySummary(for: profile),
                proxyLatency: proxyLatency(for: profile),
                isBusy: model.busyProfileID == profile.id
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("profile.\(profile.id.uuidString)")
        .disabled(model.busyProfileID == profile.id)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if !model.reservedProfileIDs.contains(profile.id) {
            Button("清理", systemImage: "eraser") {
                pendingClear = profile
            }
            .tint(.orange)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !model.reservedProfileIDs.contains(profile.id) {
            Button("删除", systemImage: "trash", role: .destructive) {
                pendingDeletion = profile
            }
            Button("编辑", systemImage: "pencil") {
                editorMode = .edit(profile)
            }
            .tint(.indigo)
            }
        }
        .contextMenu {
            if !model.reservedProfileIDs.contains(profile.id) {
            Button("编辑环境", systemImage: "pencil") {
                editorMode = .edit(profile)
            }
            Button("复制环境", systemImage: "plus.square.on.square") {
                do {
                    try model.duplicateProfile(profile)
                } catch {
                    model.present(error)
                }
            }
            Button("IP 检测", systemImage: "network") {
                ipDetectionProfile = profile
            }
            Button("清除缓存金额", systemImage: "dollarsign.arrow.trianglehead.counterclockwise") {
                do {
                    try model.resetCachedBalance(for: profile)
                } catch {
                    model.present(error)
                }
            }
            Button("清理网站数据", systemImage: "eraser") {
                pendingClear = profile
            }
            Divider()
            Button("删除环境", systemImage: "trash", role: .destructive) {
                pendingDeletion = profile
            }
            }
        }
    }

    private var deletionAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    private func proxySummary(for profile: BrowserProfile) -> String {
        if profile.unresolvedProxyNumber != nil { return "代理待选择 · 已阻止联网" }
        guard let number = profile.socksProxyNumber else { return "设备网络" }
        guard let proxy = model.socksProxy(for: profile) else { return "第 \(number) 号代理（缺失）" }
        return "第 \(number) 号代理\(proxy.displayCode.map { " · \($0)" } ?? "")"
    }

    private func proxyLatency(for profile: BrowserProfile) -> ProfileProxyLatency {
        if profile.unresolvedProxyNumber != nil { return .missing }
        guard profile.socksProxyNumber != nil else { return .direct }
        guard let proxy = model.socksProxy(for: profile) else { return .missing }
        let status = proxy.latestStatus
        let latency = proxy.latestLatency
        if testingProxyIDs.contains(proxy.id) {
            return .testing(status == .available ? latency : nil)
        }
        switch status {
        case .untested: return .untested
        case .unavailable: return .unavailable
        case .available:
            return latency.map { .available($0) } ?? .untested
        }
    }

    private var groupDeletionAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingGroupDeletion != nil },
            set: { if !$0 { pendingGroupDeletion = nil } }
        )
    }

    private var clearAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingClear != nil },
            set: { if !$0 { pendingClear = nil } }
        )
    }

    private var entryAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingEntry != nil },
            set: { if !$0 { pendingEntry = nil } }
        )
    }

    private func requestGroupDeletion(_ id: UUID) {
        if let onDeleteGroup {
            onDeleteGroup(id)
            return
        }

        dismiss()
        Task { @MainActor in
            await Task.yield()
            await model.deleteProfiles(inGroupID: id)
        }
    }
}

@MainActor
private struct ProfileRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let profile: BrowserProfile
    let balance: String?
    let balanceStatus: String?
    let todayCompleted: Bool
    let proxyMeasuredAt: Date?
    let proxySummary: String
    let proxyLatency: ProfileProxyLatency
    let isBusy: Bool

    var body: some View {
        HStack(spacing: 10) {
            if !dynamicTypeSize.isAccessibilitySize {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(profile.color.color.opacity(0.16))
                    Image(systemName: "person.crop.square.fill")
                        .foregroundStyle(profile.color.color)
                        .font(.title3)
                }
                .frame(width: 30, height: 34)
                .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 4) {
                nameAndLatency
                HStack(spacing: 6) {
                    Text("\(todayCompleted ? "今日已完成 · " : "")\(profile.homePageHost) · \(proxySummary)")
                        .font(.caption).lineLimit(1).truncationMode(.middle)
                    if let proxyMeasuredAt {
                        Text("测于 " + proxyMeasuredAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption2).fixedSize(horizontal: true, vertical: false)
                    }
                }
                .foregroundStyle(.secondary)
                if let balanceStatus {
                    Text(balanceStatus).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                if dynamicTypeSize.isAccessibilitySize { balanceLabel }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !dynamicTypeSize.isAccessibilitySize { balanceLabel }

            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在处理")
            }
        }
        .frame(minHeight: 44)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(profile.name)，\(proxyLatency.accessibilityDescription)\(balance.map { "，余额 \($0)" } ?? "")，\(balanceStatus ?? "")，主页 \(profile.homePageHost)，\(proxySummary)")
    }

    private var nameAndLatency: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            nameLabel
            latencyLabel
        }
    }

    private var latencyLabel: some View {
        // Use Text so automatic Label styles cannot hide the milliseconds.
        // Reserve the result's full width; only the environment name truncates.
        Text(proxyLatency.title)
            .font(.caption.monospacedDigit())
            .foregroundStyle(proxyLatency.foregroundColor)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
    }

    private var nameLabel: some View {
        Text(profile.name)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    @ViewBuilder
    private var balanceLabel: some View {
        if let balance {
            Text(balance)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("余额 \(balance)")
        }
    }
}

private enum ProfileProxyLatency {
    case direct, missing, untested, unavailable
    case testing(Int?)
    case available(Int)

    var title: String {
        switch self {
        case .direct: "直连"
        case .missing: "代理缺失"
        case .untested: "未测速"
        case .testing(let milliseconds): milliseconds.map { "\($0) ms" } ?? "测速中"
        case .unavailable: "不可用"
        case .available(let milliseconds): "\(milliseconds) ms"
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .available(let milliseconds): return "代理延迟 \(milliseconds) 毫秒"
        case .testing(let milliseconds):
            return milliseconds.map { "代理延迟 \($0) 毫秒，正在重新测速" } ?? "正在测速"
        case .direct, .missing, .untested, .unavailable: return title
        }
    }

    var foregroundColor: Color {
        switch self {
        case .available(let milliseconds), .testing(.some(let milliseconds)):
            switch milliseconds {
            case ...500: Color("ProxyLatencyFast")
            case ...2_000: Color("ProxyLatencyModerate")
            default: Color("ProxyLatencySlow")
            }
        case .direct, .missing, .untested, .unavailable, .testing(.none):
            .secondary
        }
    }
}
