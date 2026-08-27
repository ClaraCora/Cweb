import SwiftUI

@MainActor
struct ProfileListView: View {
    @Environment(AppModel.self) private var model

    @State private var editorMode: ProfileEditorMode?
    @State private var pendingDeletion: BrowserProfile?
    @State private var pendingClear: BrowserProfile?
    @State private var showsBackup = false

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            Group {
                if model.profiles.isEmpty {
                    ContentUnavailableView {
                        Label("还没有环境", systemImage: "person.crop.square.badge.plus")
                    } actions: {
                        Button("新建环境", systemImage: "plus") {
                            editorMode = .create
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(groupedProfiles) { group in
                            Section(group.name) {
                                ForEach(group.profiles) { profile in
                                    NavigationLink {
                                        BrowserView(profile: profile)
                                    } label: {
                                        ProfileRow(
                                            profile: profile,
                                            isBusy: model.busyProfileID == profile.id
                                        )
                                    }
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
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("环境")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("新建环境", systemImage: "plus") {
                            editorMode = .create
                        }
                        Button("加密备份", systemImage: "lock.doc") {
                            showsBackup = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("更多操作")
                }
            }
            .sheet(isPresented: $showsBackup) {
                BackupView()
            }
            .sheet(item: $editorMode) { mode in
                ProfileEditorView(profile: mode.profile) { submission in
                    switch submission {
                    case .create(let name, let groupName, let homePage, let userAgent, let color, let autofillUsername, let autofillPassword):
                        try model.addProfile(
                            name: name,
                            groupName: groupName,
                            homePage: homePage,
                            userAgent: userAgent,
                            color: color,
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
            .alert("删除环境？", isPresented: deletionAlertBinding, presenting: pendingDeletion) { profile in
                Button("删除", role: .destructive) {
                    Task { await model.deleteProfile(profile) }
                }
                Button("取消", role: .cancel) {}
            } message: { profile in
                Text("“\(profile.name)”的网站数据和已保存凭据都会被永久删除。")
            }
            .alert("清理网站数据？", isPresented: clearAlertBinding, presenting: pendingClear) { profile in
                Button("清理", role: .destructive) {
                    Task { await model.clearWebsiteData(for: profile) }
                }
                Button("取消", role: .cancel) {}
            } message: { profile in
                Text("将清除“\(profile.name)”的 Cookie、缓存和网站存储，但保留该环境和已保存凭据。")
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

    private var groupedProfiles: [ProfileGroup] {
        Dictionary(grouping: model.sortedProfiles, by: \.displayGroupName)
            .map { ProfileGroup(name: $0.key, profiles: $0.value) }
            .sorted { lhs, rhs in
                if lhs.name == "未分组" { return false }
                if rhs.name == "未分组" { return true }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private var deletionAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    private var clearAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingClear != nil },
            set: { if !$0 { pendingClear = nil } }
        )
    }
}

private struct ProfileGroup: Identifiable {
    let name: String
    let profiles: [BrowserProfile]

    var id: String { name }
}

@MainActor
private struct ProfileRow: View {
    let profile: BrowserProfile
    let isBusy: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(profile.color.color.opacity(0.16))
                Image(systemName: "person.crop.square.fill")
                    .foregroundStyle(profile.color.color)
                    .imageScale(.large)
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
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
        .accessibilityLabel("\(profile.name)，主页 \(profile.homePageHost)")
    }
}

private enum ProfileEditorMode: Identifiable {
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
