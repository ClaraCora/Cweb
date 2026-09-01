import SwiftUI
import WebKit

@MainActor
struct BrowserView: View {
    @Environment(AppModel.self) private var model

    @State private var session: BrowserSession
    @State private var showsCredentials = false
    @State private var showsDiagnostics = false
    @State private var showsBrowserChrome = false

    init(profile: BrowserProfile, socksProxy: SocksProxy? = nil) {
        _session = State(initialValue: BrowserSession(profile: profile, socksProxy: socksProxy))
    }

    var body: some View {
        @Bindable var session = session

        VStack(spacing: 0) {
            WebView(session.page)
                .webViewBackForwardNavigationGestures(.enabled)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showsBrowserChrome {
                BrowserBottomChrome(
                    session: session,
                    hideChrome: { showsBrowserChrome = false },
                    showDiagnostics: { showsDiagnostics = true }
                )
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !showsBrowserChrome {
                Button("显示浏览器工具栏", systemImage: "chevron.up") {
                    showsBrowserChrome = true
                }
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .padding(12)
                .accessibilityHint("显示地址栏和浏览器控制")
            }
        }
        .navigationTitle(session.profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsCredentials = true
                } label: {
                    Label("填充", systemImage: "key.fill")
                        .labelStyle(.titleAndIcon)
                }
                .disabled(session.currentOrigin?.isSecure != true)
            }
        }
        .toolbarVisibility(.hidden, for: .tabBar)
        .onChange(of: session.page.url) { _, newURL in
            session.syncAddressBar(with: newURL)
        }
        .task {
            model.markOpened(session.profile)
            session.start()
            await model.refreshBalance(for: session)
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
private struct BrowserBottomChrome: View {
    @Bindable var session: BrowserSession
    let hideChrome: () -> Void
    let showDiagnostics: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: session.page.estimatedProgress)
                .progressViewStyle(.linear)
                .tint(session.profile.color.color)
                .opacity(session.page.isLoading ? 1 : 0)
                .frame(height: 2)
                .accessibilityHidden(!session.page.isLoading)

            BrowserAddressBar(session: session, hideChrome: hideChrome)

            BrowserToolbar(
                canGoBack: session.canGoBack,
                canGoForward: session.canGoForward,
                goBack: session.goBack,
                goForward: session.goForward,
                goHome: session.goHome,
                showDiagnostics: showDiagnostics
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
        }
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

@MainActor
private struct BrowserAddressBar: View {
    @Bindable var session: BrowserSession
    let hideChrome: () -> Void

    var body: some View {
        HStack(spacing: 8) {
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
                    .lineLimit(1)
                    .onSubmit(session.navigateFromAddressBar)
                    .accessibilityLabel("地址")

                Button(
                    session.page.isLoading ? "停止" : "刷新",
                    systemImage: session.page.isLoading ? "xmark" : "arrow.clockwise"
                ) {
                    session.reloadOrStop()
                }
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(session.page.isLoading ? "停止载入" : "重新载入")
            }
            .padding(.leading, 12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button("隐藏浏览器工具栏", systemImage: "chevron.down") {
                hideChrome()
            }
            .labelStyle(.iconOnly)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityHint("收起地址栏和浏览器控制")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

@MainActor
private struct BrowserToolbar: View {
    let canGoBack: Bool
    let canGoForward: Bool
    let goBack: () -> Void
    let goForward: () -> Void
    let goHome: () -> Void
    let showDiagnostics: () -> Void

    var body: some View {
        HStack {
            toolbarButton("返回", systemImage: "chevron.backward", disabled: !canGoBack, action: goBack)
            Spacer()
            toolbarButton("前进", systemImage: "chevron.forward", disabled: !canGoForward, action: goForward)
            Spacer()
            toolbarButton("主页", systemImage: "house", action: goHome)
            Spacer()
            Menu {
                Button("网页诊断", systemImage: "waveform.path.ecg", action: showDiagnostics)
            } label: {
                Label("更多", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("更多")
        }
        .frame(maxWidth: .infinity, minHeight: 48)
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
