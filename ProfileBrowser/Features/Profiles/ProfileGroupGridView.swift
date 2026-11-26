import SwiftUI

@MainActor
struct ProfileGroupGridView: View {
    @Environment(AppModel.self) private var model

    @State private var editorMode: ProfileEditorMode?
    @State private var showsGroupOrder = false
    @State private var groupEditor: ProfileGroup?
    @State private var pendingGroupDeletion: ProfileGroup?
    @State private var pendingDeletionGroupID: UUID?
    @State private var navigationPath = NavigationPath()

    var body: some View {
        @Bindable var model = model

        NavigationStack(path: $navigationPath) {
            content
                .navigationTitle("分组")
                .navigationBarTitleDisplayMode(.inline)
                .background { WorkspaceBackdrop() }
                .navigationDestination(for: UUID.self) { groupID in
                    ProfileListView(
                        groupID: groupID,
                        onDeleteGroup: deleteGroupAndReturnHome
                    )
                }
                .sheet(isPresented: $showsGroupOrder) {
                    ProfileGroupOrderView()
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
                .sheet(item: $editorMode) { mode in
                    ProfileEditorView(profile: mode.profile) { submission in
                        switch submission {
                        case .create(let name, let groupName, let homePage, let userAgent, let color, let socksProxyNumber, let fixedProxyID, let autofillUsername, let autofillPassword):
                            try model.addProfile(
                                name: name,
                                groupName: groupName,
                                homePage: homePage,
                                userAgent: userAgent,
                                color: color,
                                socksProxyNumber: socksProxyNumber,
                                fixedProxyID: fixedProxyID,
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
                .alert("删除整个分组？", isPresented: groupDeletionAlertBinding, presenting: pendingGroupDeletion) { group in
                    Button("删除", role: .destructive) {
                        pendingGroupDeletion = nil
                        deleteGroupAndReturnHome(group.id)
                    }
                    Button("取消", role: .cancel) {}
                } message: { group in
                    Text("将永久删除“\(group.name)”中的 \(group.profiles.count) 个环境和已保存凭据。旧环境的网站数据将被弃用，且不会被新环境复用。")
                }
                .alert(item: $model.presentedError) { error in
                    Alert(
                        title: Text("操作失败"),
                        message: Text(error.message),
                        dismissButton: .default(Text("好"))
                    )
                }
                .onChange(of: navigationPath.count) { _, count in
                    guard count == 0 else { return }
                    schedulePendingGroupDeletion()
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoadingProfiles {
            ContentUnavailableView {
                Label("正在读取环境", systemImage: "externaldrive")
            } description: {
                Text("正在等待本地环境数据可用。")
            }
            .accessibilityElement(children: .combine)
        } else if !model.isProfileStoreAvailable {
            ContentUnavailableView {
                Label("无法读取环境", systemImage: "externaldrive.badge.exclamationmark")
            } description: {
                Text("原数据没有被修改，可以重新尝试读取。")
            } actions: {
                Button("重新读取", systemImage: "arrow.clockwise") {
                    Task { await model.retryLoadingProfiles() }
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            groupList
        }
    }

    private var groupList: some View {
        let groups = model.profileGroups
        // Bound each live glass surface when the user has many groups.
        let rowsPerPanel = 8
        let panelStarts = Array(stride(from: 0, to: groups.count, by: rowsPerPanel))

        return List {
            Section {
                groupOverview
                    .listRowInsets(EdgeInsets(top: 8, leading: AppUI.workspaceInset, bottom: 18, trailing: AppUI.workspaceInset))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            Section {
                if groups.isEmpty {
                    ContentUnavailableView {
                        Label("还没有分组", systemImage: "folder.badge.plus")
                    } description: {
                        Text("新建环境后，会按所属分组显示在这里。")
                            .font(.subheadline)
                            .foregroundStyle(AppUI.secondaryText)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: AppUI.workspaceInset, bottom: 0, trailing: AppUI.workspaceInset))
                }
                ForEach(panelStarts, id: \.self) { start in
                    let end = min(start + rowsPerPanel, groups.count)
                    let panelGroups = groups[start..<end]
                    VStack(spacing: 0) {
                        ForEach(panelGroups) { group in
                            groupButton(group, canReorder: groups.count > 1)
                            if group.id != panelGroups.last?.id {
                                Divider()
                                    .padding(.leading, 72)
                                    .padding(.trailing, 16)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .beamPanel(cornerRadius: AppUI.panelRadius, active: true)
                    .listRowInsets(EdgeInsets(top: 0, leading: AppUI.workspaceInset, bottom: 12, trailing: AppUI.workspaceInset))
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .listSectionSpacing(0)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("groups.list")
    }

    private func groupButton(_ group: ProfileGroup, canReorder: Bool) -> some View {
        let isBusy = model.busyGroupName == group.name
        return Button {
            navigationPath.append(group.id)
        } label: {
            ProfileGroupRow(group: group, isBusy: isBusy)
        }
        .buttonStyle(WorkspaceRowButtonStyle())
        .accessibilityIdentifier("group.\(group.id.uuidString)")
        .disabled(isBusy)
        .contextMenu {
            Button("编辑分组", systemImage: "pencil") {
                groupEditor = group
            }
            Button("调整分组排序", systemImage: "arrow.up.arrow.down") {
                showsGroupOrder = true
            }
            .disabled(!canReorder)
            Button("删除整个分组", systemImage: "trash", role: .destructive) {
                pendingGroupDeletion = group
            }
        }
    }

    private var groupOverview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 48, height: 48)
                    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("环境分组")
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("\(model.profileGroups.count) 个分组 · \(model.profiles.count) 个环境")
                        .font(.footnote)
                        .foregroundStyle(AppUI.secondaryText)
                        .monospacedDigit()
                        .accessibilityIdentifier("groups.summary")
                }
            }

            HStack(spacing: 8) {
                Button {
                    editorMode = .create
                } label: {
                    Label("新建环境", systemImage: "plus")
                }
                .buttonStyle(WorkspaceActionStyle(prominent: true))
                .disabled(!model.isProfileStoreAvailable)
                .accessibilityIdentifier("groups.create")

                Button {
                    showsGroupOrder = true
                } label: {
                    Label("分组排序", systemImage: "arrow.up.arrow.down")
                }
                .buttonStyle(WorkspaceActionStyle())
                .disabled(model.profileGroups.count < 2)
                .accessibilityIdentifier("groups.reorder")
            }
        }
        .padding(AppUI.Spacing.page)
        .beamPanel(cornerRadius: AppUI.overviewRadius, active: true)
    }

    private var groupDeletionAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingGroupDeletion != nil },
            set: { if !$0 { pendingGroupDeletion = nil } }
        )
    }

    private func deleteGroupAndReturnHome(_ groupID: UUID) {
        let wasAtHome = navigationPath.isEmpty
        pendingDeletionGroupID = groupID
        if !wasAtHome {
            navigationPath = NavigationPath()
            return
        }

        schedulePendingGroupDeletion()
    }

    private func schedulePendingGroupDeletion() {
        guard let groupID = pendingDeletionGroupID else { return }
        pendingDeletionGroupID = nil
        Task { @MainActor in
            await Task.yield()
            await model.deleteProfiles(inGroupID: groupID)
        }
    }
}

private struct ProfileGroupRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let group: ProfileGroup
    let isBusy: Bool

    var body: some View {
        HStack(spacing: AppUI.Spacing.row) {
            ProfileGroupIcon(emoji: group.emoji)

            VStack(alignment: .leading, spacing: AppUI.Spacing.tight) {
                Text(group.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .truncationMode(.tail)

                if let code = group.displayCode {
                    Text(code)
                        .font(.footnote.monospaced())
                        .foregroundStyle(AppUI.secondaryText)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                } else {
                    Text(codePlaceholder)
                        .font(.footnote)
                        .foregroundStyle(AppUI.secondaryText)
                }

                if dynamicTypeSize.isAccessibilitySize { environmentCount }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !dynamicTypeSize.isAccessibilitySize { environmentCount }

            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在删除分组")
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(16)
        .frame(minHeight: 84)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.name)\(group.displayCode.map { "，代号 \($0)" } ?? "，\(codePlaceholder)")，\(group.profiles.count) 个环境\(isBusy ? "，正在删除分组" : "")")
        .accessibilityHint("进入分组")
    }

    private var codePlaceholder: String {
        group.name == "未分组" ? "默认分组" : "未设置代号"
    }

    private var environmentCount: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(group.profiles.count, format: .number)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.primary)
            Text("个环境")
                .font(.caption)
                .foregroundStyle(AppUI.secondaryText)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

enum ProfileEditorMode: Identifiable {
    case create
    case edit(BrowserProfile)

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let profile): profile.id.uuidString
        }
    }

    var profile: BrowserProfile? {
        switch self {
        case .create: nil
        case .edit(let profile): profile
        }
    }
}
