import SwiftUI

@MainActor
struct ProfileListView: View {
    @Environment(AppModel.self) private var model

    let groupName: String

    @State private var editorMode: ProfileEditorMode?
    @State private var pendingDeletion: BrowserProfile?
    @State private var pendingClear: BrowserProfile?
    @State private var pendingEntry: BrowserProfile?
    @State private var activeProfile: BrowserProfile?
    @State private var editMode: EditMode = .inactive

    init(groupName: String) {
        self.groupName = groupName
    }

    var body: some View {
        @Bindable var model = model

        content
            .navigationTitle(groupName)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $activeProfile) { profile in
                BrowserView(profile: profile)
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    EditButton()
                    Button("新建", systemImage: "plus") {
                        editorMode = .create
                    }
                }
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
        model.sortedProfiles.filter { $0.displayGroupName == groupName }
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
