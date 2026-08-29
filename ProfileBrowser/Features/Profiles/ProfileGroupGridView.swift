import SwiftUI

@MainActor
struct ProfileGroupGridView: View {
    @Environment(AppModel.self) private var model

    @State private var editorMode: ProfileEditorMode?
    @State private var showsBackup = false

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            content
                .navigationTitle("分组")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: String.self) { groupName in
                    ProfileListView(groupName: groupName)
                }
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("新建", systemImage: "plus") {
                            editorMode = .create
                        }
                        Menu {
                            Button("备份", systemImage: "lock.doc") {
                                showsBackup = true
                            }
                        } label: {
                            Label("更多", systemImage: "ellipsis.circle")
                        }
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
                .alert(item: $model.presentedError) { error in
                    Alert(
                        title: Text("操作失败"),
                        message: Text(error.message),
                        dismissButton: .default(Text("好"))
                    )
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.profileGroups.isEmpty {
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
                        NavigationLink(value: group.name) {
                            ProfileGroupCard(group: group)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .background(Color(.systemGroupedBackground))
        }
    }
}

private struct ProfileGroupCard: View {
    let group: ProfileGroup

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.3.group.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(group.color.color)
                .frame(width: 28, height: 28)

            Text(group.name)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .layoutPriority(1)

            Spacer(minLength: 4)

            Text("\(group.profiles.count)")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
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
        .accessibilityLabel("\(group.name)，\(group.profiles.count) 个环境")
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
