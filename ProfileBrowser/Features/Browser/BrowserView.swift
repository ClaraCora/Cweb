import SwiftUI
import WebKit

@MainActor
struct BrowserView: View {
    @Environment(AppModel.self) private var model

    @State private var session: BrowserSession
    @State private var showsCredentials = false
    @State private var showsDiagnostics = false

    init(profile: BrowserProfile) {
        _session = State(initialValue: BrowserSession(profile: profile))
    }

    var body: some View {
        @Bindable var session = session

        VStack(spacing: 0) {
            BrowserAddressBar(session: session)

            ProgressView(value: session.page.estimatedProgress)
                .progressViewStyle(.linear)
                .tint(session.profile.color.color)
                .opacity(session.page.isLoading ? 1 : 0)
                .frame(height: 2)
                .accessibilityHidden(!session.page.isLoading)

            WebView(session.page)
                .webViewBackForwardNavigationGestures(.enabled)
        }
        .navigationTitle(session.profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Label(session.profile.name, systemImage: "person.crop.square.fill")
                    .foregroundStyle(session.profile.color.color)
                    .font(.headline)
                    .lineLimit(1)
                    .accessibilityLabel("当前环境：\(session.profile.name)")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsCredentials = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "key.fill")
                        Text("填充密码")
                    }
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .tint(Color.accentColor)
                .disabled(session.currentOrigin?.isSecure != true)
                .accessibilityLabel("填充密码")
            }
            ToolbarItem(placement: .bottomBar) {
                BrowserToolbar(
                    canGoBack: session.canGoBack,
                    canGoForward: session.canGoForward,
                    isLoading: session.page.isLoading,
                    credentialsEnabled: session.currentOrigin?.isSecure == true,
                    goBack: session.goBack,
                    goForward: session.goForward,
                    goHome: session.goHome,
                    reloadOrStop: session.reloadOrStop,
                    showCredentials: { showsCredentials = true },
                    showDiagnostics: { showsDiagnostics = true }
                )
            }
        }
        .onChange(of: session.page.url) { _, newURL in
            session.syncAddressBar(with: newURL)
        }
        .task {
            model.markOpened(session.profile)
            session.start()
        }
        .sheet(isPresented: $showsCredentials) {
            if let origin = session.currentOrigin, origin.isSecure {
                CredentialListView(
                    profile: session.profile,
                    origin: origin,
                    vault: model.credentialVault,
                    onFill: session.fill
                )
            }
        }
        .sheet(isPresented: $showsDiagnostics) {
            DiagnosticsView(session: session)
        }
        .alert(item: $session.presentedError) { error in
            Alert(
                title: Text("无法打开页面"),
                message: Text(error.message),
                dismissButton: .default(Text("好"))
            )
        }
    }
}

@MainActor
private struct BrowserAddressBar: View {
    @Bindable var session: BrowserSession

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: session.currentOrigin?.isSecure == true ? "lock.fill" : "globe")
                .foregroundStyle(session.currentOrigin?.isSecure == true ? .green : .secondary)
                .frame(width: 20)
                .accessibilityLabel(session.currentOrigin?.isSecure == true ? "安全连接" : "网址")

            TextField("网址或搜索内容", text: $session.addressText)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit(session.navigateFromAddressBar)
                .accessibilityLabel("地址")

            Button("前往", systemImage: "arrow.right.circle.fill") {
                session.navigateFromAddressBar()
            }
            .labelStyle(.iconOnly)
            .font(.title3)
            .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
        .background(.bar)
    }
}

@MainActor
private struct BrowserToolbar: View {
    let canGoBack: Bool
    let canGoForward: Bool
    let isLoading: Bool
    let credentialsEnabled: Bool
    let goBack: () -> Void
    let goForward: () -> Void
    let goHome: () -> Void
    let reloadOrStop: () -> Void
    let showCredentials: () -> Void
    let showDiagnostics: () -> Void

    var body: some View {
        HStack {
            toolbarButton("返回", systemImage: "chevron.backward", disabled: !canGoBack, action: goBack)
            Spacer()
            toolbarButton("前进", systemImage: "chevron.forward", disabled: !canGoForward, action: goForward)
            Spacer()
            toolbarButton("主页", systemImage: "house", action: goHome)
            Spacer()
            toolbarButton(isLoading ? "停止" : "刷新", systemImage: isLoading ? "xmark" : "arrow.clockwise", action: reloadOrStop)
            Spacer()
            toolbarButton("凭据", systemImage: "key", disabled: !credentialsEnabled, action: showCredentials)
            Spacer()
            toolbarButton("诊断", systemImage: "waveform.path.ecg", action: showDiagnostics)
        }
        .frame(maxWidth: .infinity)
    }

    private func toolbarButton(
        _ label: String,
        systemImage: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(label, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .frame(minWidth: 44, minHeight: 44)
            .disabled(disabled)
            .accessibilityLabel(label)
    }
}
