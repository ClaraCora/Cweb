import SwiftUI
import WebKit

@MainActor
struct BrowserView: View {
    @Environment(AppModel.self) private var model

    @State private var session: BrowserSession
    @State private var showsCredentials = false
    @State private var showsDiagnostics = false
    @State private var showsBrowserChrome = false
    @State private var showsFillUnavailable = false

    init(profile: BrowserProfile, socksProxy: SocksProxy? = nil) {
        _session = State(initialValue: BrowserSession(profile: profile, socksProxy: socksProxy))
    }

    var body: some View {
        @Bindable var session = session

        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: session.currentOrigin?.isSecure == true ? "lock" : "globe")
                        .accessibilityHidden(true)
                    Text(session.currentOrigin?.host ?? session.profile.homePageHost)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 28)
                .padding(.horizontal, 16)

                ProgressView(value: session.page.estimatedProgress)
                    .tint(.accentColor)
                    .opacity(session.page.isLoading ? 1 : 0)
                    .frame(height: 2)
                    .accessibilityHidden(!session.page.isLoading)
            }
            .background(.bar)

            WebView(session.page)
                .webViewBackForwardNavigationGestures(.enabled)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("browser.webPage")

            if showsBrowserChrome {
                BrowserBottomChrome(
                    session: session,
                    hideChrome: { showsBrowserChrome = false },
                    showDiagnostics: { showsDiagnostics = true }
                )
            } else {
                HStack {
                    Spacer()
                    Button("显示浏览器工具栏", systemImage: "chevron.up") {
                        showsBrowserChrome = true
                    }
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityIdentifier("browser.showToolbar")
                    .accessibilityHint("显示地址栏和浏览器控制")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(.bar)
            }
        }
        .navigationTitle(session.profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if session.currentOrigin?.isSecure == true {
                        showsCredentials = true
                    } else {
                        showsFillUnavailable = true
                    }
                } label: {
                    Label("填充", systemImage: "key.fill")
                        .labelStyle(.titleAndIcon)
                }
                .accessibilityIdentifier("browser.fill")
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
        .alert("暂时无法填充", isPresented: $showsFillUnavailable) {
            Button("好", role: .cancel) {}
        } message: {
            Text("请等待 HTTPS 页面载入后再填充账号密码。")
        }
        .alert("无法打开页面", isPresented: errorBinding, presenting: session.presentedError) { _ in
            Button("重试") { session.navigateFromAddressBar() }
            Button("取消", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { session.presentedError != nil },
            set: { if !$0 { session.presentedError = nil } }
        )
    }
}

@MainActor
private struct BrowserBottomChrome: View {
    @Bindable var session: BrowserSession
    let hideChrome: () -> Void
    let showDiagnostics: () -> Void

    var body: some View {
        VStack(spacing: 0) {
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
            .accessibilityIdentifier("browser.hideToolbar")
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
