import SwiftUI

@MainActor
struct ProfileListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let groupID: UUID
    let onDeleteGroup: ((UUID) -> Void)?

    @State private var editorMode: ProfileEditorMode?
    @State private var groupEditor: ProfileGroup?
    @State private var pendingGroupDeletion: ProfileGroup?
    @State private var pendingDeletion: BrowserProfile?
    @State private var pendingClear: BrowserProfile?
    @State private var pendingEntry: BrowserProfile?
    @State private var activeProfile: BrowserProfile?
    @State private var editMode: EditMode = .inactive

    init(groupID: UUID, onDeleteGroup: ((UUID) -> Void)? = nil) {
        self.groupID = groupID
        self.onDeleteGroup = onDeleteGroup
    }

    var body: some View {
        @Bindable var model = model

        content
            .navigationTitle(currentGroup?.name ?? "分组")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $activeProfile) { profile in
                BrowserView(profile: profile, socksProxy: model.socksProxy(for: profile))
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    EditButton()
                    Button("新建", systemImage: "plus") {
                        editorMode = .create
                    }
                    Menu {
                        if let currentGroup {
                            Button("编辑分组", systemImage: "pencil") {
                                groupEditor = currentGroup
                            }
                        }
                        Button("删除整个分组", systemImage: "trash", role: .destructive) {
                            if let currentGroup {
                                pendingGroupDeletion = currentGroup
                            }
                        }
                        .disabled(currentGroup == nil)
                    } label: {
                        Label("更多", systemImage: "ellipsis.circle")
                    }
                }
            }
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
                    if visibleProfiles.count == 1,
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
            .alert("进入环境？", isPresented: entryAlertBinding, presenting: pendingEntry) { profile in
                Button("进入") {
                    pendingEntry = nil
                    activeProfile = profile
                }
                Button("取消", role: .cancel) {}
            } message: { profile in
                Text("将使用“\(profile.name)”的独立网站数据和 User-Agent 打开主页。")
            }
            .alert(item: $model.presentedError) { error in
                Alert(
                    title: Text("操作失败"),
                    message: Text(error.message),
                    dismissButton: .default(Text("好"))
                )
            }
            .environment(\.editMode, $editMode)
    }

    @ViewBuilder
    private var content: some View {
        if visibleProfiles.isEmpty {
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
            }
            .listStyle(.insetGrouped)
        }
    }

    private var visibleProfiles: [BrowserProfile] {
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

    private func profileButton(for profile: BrowserProfile) -> some View {
        Button {
            guard editMode != .active else { return }
            pendingEntry = profile
        } label: {
            ProfileRow(
                profile: profile,
                balance: model.balance(for: profile),
                isBusy: model.busyProfileID == profile.id
            )
        }
        .buttonStyle(.plain)
        .disabled(model.busyProfileID == profile.id)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button("清理", systemImage: "eraser") {
                pendingClear = profile
            }
            .tint(.orange)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("删除", systemImage: "trash", role: .destructive) {
                pendingDeletion = profile
            }
            Button("编辑", systemImage: "pencil") {
                editorMode = .edit(profile)
            }
            .tint(.indigo)
        }
        .contextMenu {
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
            Button("余额清零", systemImage: "dollarsign.arrow.trianglehead.counterclockwise") {
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

    private var deletionAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
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
    let profile: BrowserProfile
    let balance: String?
    let isBusy: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(profile.color.color.opacity(0.16))
                Image(systemName: "person.crop.square.fill")
                    .foregroundStyle(profile.color.color)
                    .imageScale(.large)
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(profile.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .layoutPriority(1)
                    if let balance {
                        Text(balance)
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Text(profile.homePageHost)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在处理")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(profile.name)\(balance.map { "，余额 \($0)" } ?? "")，主页 \(profile.homePageHost)")
    }
}
