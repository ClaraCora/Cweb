import SwiftUI

private struct EditorDismissProtection: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    @State private var showsDiscardConfirmation = false

    let isModified: Bool
    let isBusy: Bool

    func body(content: Content) -> some View {
        content
            .interactiveDismissDisabled(isModified || isBusy)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        if isModified {
                            showsDiscardConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(isBusy)
                    .accessibilityIdentifier("editor.cancel")
                }
            }
            .confirmationDialog("放弃未保存的修改？", isPresented: $showsDiscardConfirmation, titleVisibility: .visible) {
                Button("放弃修改", role: .destructive) { dismiss() }
                Button("继续编辑", role: .cancel) {}
            }
    }
}

extension View {
    func editorDismissProtection(isModified: Bool, isBusy: Bool = false) -> some View {
        modifier(EditorDismissProtection(isModified: isModified, isBusy: isBusy))
    }
}
