import SwiftUI

@MainActor
struct ProfileGroupSelectionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String
    @State private var newName = ""
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    groupButton("未分组", value: "")
                    ForEach(model.profileGroups.filter { group in
                        group.name != "未分组" && (searchText.isEmpty || group.name.localizedCaseInsensitiveContains(searchText))
                    }) { group in
                        groupButton(group.name, value: group.name)
                    }
                }
                Section("新分组") {
                    FormField("分组名称") {
                        TextField("分组名称", text: $newName)
                            .autocorrectionDisabled()
                    }
                    Button("使用新分组", systemImage: "plus") {
                        selection = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                        dismiss()
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .searchable(text: $searchText, prompt: "查找分组")
            .navigationTitle("选择分组")
            .navigationBarTitleDisplayMode(.inline)
            .editorDismissProtection(isModified: !newName.isEmpty)
        }
    }

    private func groupButton(_ title: String, value: String) -> some View {
        Button {
            selection = value
            dismiss()
        } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if selection == value {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
            .frame(minHeight: 44)
        }
        .accessibilityAddTraits(selection == value ? .isSelected : [])
    }
}

@MainActor
struct ProfileProxySelectionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: Int?
    let groupName: String?
    let profileID: UUID?
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        selection = nil
                        dismiss()
                    } label: {
                        HStack {
                            Text("不使用代理").foregroundStyle(.primary)
                            Spacer()
                            if selection == nil { Image(systemName: "checkmark") }
                        }
                        .frame(minHeight: 44)
                    }
                }
                Section {
                    ForEach(options) { ranking in
                        let occupant = model.profileUsingSocksProxyNumber(
                            ranking.number, inGroupNamed: groupName, excludingProfileID: profileID
                        )
                        Button {
                            selection = ranking.number
                            dismiss()
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("第 \(ranking.number) 号\(ranking.proxy.displayCode.map { " · \($0)" } ?? "")")
                                        .foregroundStyle(.primary)
                                    Text(ranking.proxy.displayAddress)
                                        .font(.subheadline.monospaced())
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if let occupant {
                                        Text("已由“\(occupant.name)”使用")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                                if selection == ranking.number { Image(systemName: "checkmark") }
                            }
                            .padding(.vertical, 4)
                            .frame(minHeight: 44)
                        }
                        .disabled(occupant != nil)
                        .accessibilityIdentifier("proxyOption.\(ranking.number)")
                        .accessibilityAddTraits(selection == ranking.number ? .isSelected : [])
                    }
                } footer: {
                    Text("同一分组内每个编号只能使用一次；编号内容随代理重新排序而变化。")
                }
            }
            .searchable(text: $searchText, prompt: "编号、代号或地址")
            .navigationTitle("选择代理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private var options: [SocksProxyRanking] {
        model.rankedSocksProxies.filter { ranking in
            searchText.isEmpty || "\(ranking.number) \(ranking.proxy.displayCode ?? "") \(ranking.proxy.displayAddress)"
                .localizedCaseInsensitiveContains(searchText)
        }
    }
}
