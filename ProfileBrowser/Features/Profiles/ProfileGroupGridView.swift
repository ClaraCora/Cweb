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
                .background(Color(.systemGroupedBackground))
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
                .task {
                    await model.retryLoadingProfiles()
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

        return List {
            Section {
                groupOverview
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 24, trailing: 20))
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
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                }
                ForEach(groups) { group in
                    Button {
                        navigationPath.append(group.id)
                    } label: {
                        ProfileGroupRow(
                            group: group,
                            isBusy: model.busyGroupName == group.name
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("group.\(group.id.uuidString)")
                    .disabled(model.busyGroupName == group.name)
                    .background {
                        UnevenRoundedRectangle(
                            topLeadingRadius: group.id == groups.first?.id ? 16 : 0,
                            bottomLeadingRadius: group.id == groups.last?.id ? 16 : 0,
                            bottomTrailingRadius: group.id == groups.last?.id ? 16 : 0,
                            topTrailingRadius: group.id == groups.first?.id ? 16 : 0
                        )
                        .fill(Color(.secondarySystemGroupedBackground))
                    }
                    .overlay(alignment: .bottom) {
                        if group.id != groups.last?.id {
                            Divider().padding(.leading, 72).padding(.trailing, 16)
                        }
                    }
                    .contextMenu {
                        Button("编辑分组", systemImage: "pencil") {
                            groupEditor = group
                        }
                        Button("调整分组排序", systemImage: "arrow.up.arrow.down") {
                            showsGroupOrder = true
                        }
                        .disabled(groups.count < 2)
                        Button("删除整个分组", systemImage: "trash", role: .destructive) {
                            pendingGroupDeletion = group
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
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

    private var groupOverview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 48, height: 48)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("环境分组")
                        .font(.title3.weight(.semibold))
                    Text("\(model.profileGroups.count) 个分组 · \(model.profiles.count) 个环境")
                        .font(.footnote)
                        .foregroundStyle(AppUI.secondaryText)
                        .monospacedDigit()
                        .accessibilityIdentifier("groups.summary")
                }
            }

            HStack(spacing: 12) {
                Button {
                    editorMode = .create
                } label: {
                    Label("新建环境", systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(Color(.systemBackground))
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!model.isProfileStoreAvailable)
                .accessibilityIdentifier("groups.create")

                Button {
                    showsGroupOrder = true
                } label: {
                    Label("分组排序", systemImage: "arrow.up.arrow.down")
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(Color.accentColor)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(model.profileGroups.count < 2)
                .opacity(model.profileGroups.count < 2 ? 0.45 : 1)
                .accessibilityIdentifier("groups.reorder")
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.plain)
        }
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
            groupIcon
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)

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

    @ViewBuilder
    private var groupIcon: some View {
        if let emoji = group.emoji?.trimmingCharacters(in: .whitespacesAndNewlines), !emoji.isEmpty {
            Text(emoji)
                .font(.title2)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        } else {
            Image(systemName: "folder.fill")
                .font(.title3.weight(.medium))
                .foregroundStyle(Color.accentColor)
        }
    }

    private var codePlaceholder: String {
        group.name == "未分组" ? "默认分组" : "未设置代号"
    }

    private var environmentCount: some View {
        Text("\(group.profiles.count) 个环境")
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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
