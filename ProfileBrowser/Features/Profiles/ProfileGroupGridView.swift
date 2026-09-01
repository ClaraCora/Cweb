import SwiftUI

@MainActor
struct ProfileGroupGridView: View {
    @Environment(AppModel.self) private var model

    @State private var editorMode: ProfileEditorMode?
    @State private var showsBackup = false
    @State private var showsSocksProxyManager = false
    @State private var showsSettings = false
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
                .navigationDestination(for: UUID.self) { groupID in
                    ProfileListView(
                        groupID: groupID,
                        onDeleteGroup: deleteGroupAndReturnHome
                    )
                }
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("新建", systemImage: "plus") {
                            editorMode = .create
                        }
                        .disabled(!model.isProfileStoreAvailable)
                        Button("设置", systemImage: "gearshape") {
                            showsSettings = true
                        }
                        Menu {
                            Button("分组排序", systemImage: "arrow.up.arrow.down") {
                                showsGroupOrder = true
                            }
                            .disabled(model.profileGroups.count < 2)
                            Button("备份", systemImage: "lock.doc") {
                                showsBackup = true
                            }
                            Button("SOCKS 代理", systemImage: "network") {
                                showsSocksProxyManager = true
                            }
                        } label: {
                            Label("更多", systemImage: "ellipsis.circle")
                        }
                    }
                }
                .sheet(isPresented: $showsBackup) {
                    BackupView()
                }
                .navigationDestination(isPresented: $showsSocksProxyManager) {
                    SocksProxyListView()
                }
                .sheet(isPresented: $showsSettings) {
                    NavigationStack {
                        SettingsView()
                    }
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
        } else if model.profileGroups.isEmpty {
            ContentUnavailableView {
                Label("还没有分组", systemImage: "rectangle.3.group.badge.plus")
            } actions: {
                Button("新建环境", systemImage: "plus") {
                    editorMode = .create
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    ForEach(model.profileGroups) { group in
                        NavigationLink(value: group.id) {
                            ProfileGroupCard(
                                group: group,
                                isBusy: model.busyGroupName == group.name
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(model.busyGroupName == group.name)
                        .contextMenu {
                            Button("编辑分组", systemImage: "pencil") {
                                groupEditor = group
                            }
                            Button("调整分组排序", systemImage: "arrow.up.arrow.down") {
                                showsGroupOrder = true
                            }
                            .disabled(model.profileGroups.count < 2)
                            Button("删除整个分组", systemImage: "trash", role: .destructive) {
                                pendingGroupDeletion = group
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .background(Color(.systemGroupedBackground))
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

private struct ProfileGroupCard: View {
    let group: ProfileGroup
    let isBusy: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(group.displayEmoji)
                .font(.title2)
                .frame(width: 34, height: 34)
                .background(group.color.color.opacity(0.14), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(group.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .layoutPriority(1)
                    if let code = group.displayCode {
                        Text(code)
                            .font(.caption.monospaced().weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Text("\(group.profiles.count) 个环境")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在删除分组")
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .background(
            group.color.color.opacity(0.14),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(group.color.color.opacity(0.24), lineWidth: 0.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.displayEmoji)，\(group.name)\(group.displayCode.map { "，代号 \($0)" } ?? "")，\(group.profiles.count) 个环境")
        .accessibilityHint("进入分组")
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
