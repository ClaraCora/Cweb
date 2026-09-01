import SwiftUI

@MainActor
struct ProfileGroupOrderView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            List {
                ForEach(model.profileGroups) { group in
                    HStack(spacing: 12) {
                        Text(group.displayEmoji)
                            .font(.title3)
                            .frame(width: 32, height: 32)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.name)
                                .font(.body.weight(.medium))
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                if let code = group.displayCode {
                                    Text(code)
                                        .font(.caption.monospaced())
                                }
                                Text("\(group.profiles.count) 个环境")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(group.name)，\(group.profiles.count) 个环境")
                    .accessibilityHint("上下拖动调整顺序")
                }
                .onMove { offsets, destination in
                    do {
                        try model.moveGroups(fromOffsets: offsets, toOffset: destination)
                    } catch {
                        model.present(error)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("分组排序")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .environment(\.editMode, .constant(.active))
            .alert(item: $model.presentedError) { error in
                Alert(
                    title: Text("排序失败"),
                    message: Text(error.message),
                    dismissButton: .default(Text("好"))
                )
            }
        }
    }
}
