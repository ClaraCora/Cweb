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
                .navigationBarTitleDisplayMode(.large)
                .navigationDestination(for: UUID.self) { groupID in
                    ProfileListView(
                        groupID: groupID,
                        onDeleteGroup: deleteGroupAndReturnHome
                    )
                }
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("排序") {
                            showsGroupOrder = true
                        }
                        .accessibilityLabel("分组排序")
                        .disabled(model.profileGroups.count < 2)

                        Button("新建环境", systemImage: "plus") {
                            editorMode = .create
                        }
                        .disabled(!model.isProfileStoreAvailable)
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
            List {
                Section {
                    ForEach(model.profileGroups) { group in
                        NavigationLink(value: group.id) {
                            ProfileGroupRow(
                                group: group,
                                isBusy: model.busyGroupName == group.name
                            )
                        }
                        .accessibilityIdentifier("group.\(group.id.uuidString)")
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
                } header: {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            Text("\(model.profileGroups.count) 个分组")
                                .fixedSize()
                            Spacer(minLength: 8)
                            Text("\(model.profiles.count) 个环境")
                                .fixedSize()
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(model.profileGroups.count) 个分组")
                            Text("\(model.profiles.count) 个环境")
                        }
                    }
                    .font(.subheadline)
                    .textCase(nil)
                    .accessibilityElement(children: .combine)
                }
            }
            .listStyle(.insetGrouped)
            .readableListMargins()
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
            Text(group.displayEmoji)
                .font(.title2)
                .frame(minWidth: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppUI.Spacing.tight) {
                Text(group.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .truncationMode(.tail)

                if let code = group.displayCode {
                    Text(code)
                        .font(.caption.monospaced())
                        .foregroundStyle(AppUI.secondaryText)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                } else {
                    Text(codePlaceholder)
                        .font(.caption)
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
            }
        }
        .frame(minHeight: 44)
        .padding(.vertical, AppUI.Spacing.tight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.displayEmoji)，\(group.name)\(group.displayCode.map { "，代号 \($0)" } ?? "，\(codePlaceholder)")，\(group.profiles.count) 个环境\(isBusy ? "，正在删除分组" : "")")
        .accessibilityHint("进入分组")
    }

    private var codePlaceholder: String {
        group.name == "未分组" ? "默认分组" : "未设置代号"
    }

    private var environmentCount: some View {
        Text("\(group.profiles.count) 个环境")
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(AppUI.secondaryText)
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
