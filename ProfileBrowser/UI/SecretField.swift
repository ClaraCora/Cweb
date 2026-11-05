import SwiftUI

/// Passwords remain concealed until the user explicitly reveals them.
struct SecretField: View {
    let title: String
    @Binding var text: String
    @Environment(\.scenePhase) private var scenePhase
    @State private var revealed = false

    init(_ title: String, text: Binding<String>) { self.title = title; _text = text }

    var body: some View {
        HStack {
            Group {
                if revealed { TextField(title, text: $text) }
                else { SecureField(title, text: $text) }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            Button(revealed ? "隐藏密码" : "显示密码", systemImage: revealed ? "eye.slash" : "eye") {
                revealed.toggle()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .frame(minWidth: 44, minHeight: 44)
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { revealed = false } }
    }
}
