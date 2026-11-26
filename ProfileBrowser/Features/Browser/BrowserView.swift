import SwiftUI
import WebKit

@MainActor
struct BrowserView: View {
    @Environment(AppModel.self) private var model
    private let automationSettings: GlobalScriptSettings?
    private let automationIsPaused: Bool
    private let automaticallyRefreshesBalance: Bool
    private let onAutomationEvent: (@MainActor (UUID, AutomationEvent) -> Void)?
    private let browserChromePresentation: Binding<Bool>?

    @State private var session: BrowserSession
    @State private var showsCredentials = false
    @State private var showsDiagnostics = false
    @State private var showsBrowserChrome = false
    @State private var showsFillUnavailable = false
    @State private var showsWebsiteRules = false
    @State private var balanceFeedback: String?
    @Environment(\.scenePhase) private var scenePhase

    init(profile: BrowserProfile, socksProxy: SocksProxy? = nil) {
        _session = State(initialValue: BrowserSession(profile: profile, socksProxy: socksProxy))
        automationSettings = nil
        automationIsPaused = false
        automaticallyRefreshesBalance = true
        onAutomationEvent = nil
        browserChromePresentation = nil
    }

    init(
        session: BrowserSession,
        automationSettings: GlobalScriptSettings,
        automationIsPaused: Bool = false,
        automaticallyRefreshesBalance: Bool = true,
        browserChromePresentation: Binding<Bool>? = nil,
        onAutomationEvent: @escaping @MainActor (UUID, AutomationEvent) -> Void
    ) {
        _session = State(initialValue: session)
        self.automationSettings = automationSettings
        self.automationIsPaused = automationIsPaused
        self.automaticallyRefreshesBalance = automaticallyRefreshesBalance
        self.browserChromePresentation = browserChromePresentation
        self.onAutomationEvent = onAutomationEvent
    }

    var body: some View {
        @Bindable var session = session

        VStack(spacing: 0) {
            // A group run shows the host in its navigation title and status in its task bar.
            if browserChromePresentation == nil {
                HStack(spacing: 6) {
                    Image(systemName: session.currentOrigin?.isSecure == true ? "lock" : "globe")
                        .accessibilityHidden(true)
                    Text(session.currentOrigin?.host ?? session.profile.homePageHost)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
                .font(.subheadline)
                .foregroundStyle(AppUI.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 28)
                .padding(.horizontal, 16)
                .background(Color(uiColor: .systemGroupedBackground))
            }

            ProgressView(value: session.page.estimatedProgress)
                .tint(.accentColor)
                .opacity(session.page.isLoading ? 1 : 0)
                .frame(height: 2)
                .accessibilityHidden(!session.page.isLoading)
                .background(Color(uiColor: .systemGroupedBackground))

            if browserChromePresentation == nil, let automationMessage = session.automationMessage {
                AutomationStatusBanner(
                    state: session.automationState,
                    message: automationMessage,
                    resume: {
                        Task { await session.resumeAutomation() }
                    }
                )
                .disabled(automationIsPaused)
            }

            WebView(session.page)
                .webViewBackForwardNavigationGestures(.enabled)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("browser.webPage")
                .overlay(alignment: .bottomTrailing) {
                    if browserChromePresentation == nil, !browserChromeBinding.wrappedValue {
                        Button {
                            showsBrowserChrome = true
                        } label: {
                            Label("显示浏览器工具栏", systemImage: "chevron.up")
                                .labelStyle(.iconOnly)
                                .frame(minWidth: AppUI.minimumTarget, minHeight: AppUI.minimumTarget)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .padding(AppUI.Spacing.row)
                        .accessibilityIdentifier("browser.showToolbar")
                        .accessibilityHint("显示地址栏和浏览器控制")
                    }
                }

            if browserChromeBinding.wrappedValue {
                BrowserBottomChrome(
                    session: session,
                    hideChrome: { browserChromeBinding.wrappedValue = false },
                    showDiagnostics: { showsDiagnostics = true }
                )
            }
        }
        .navigationTitle(session.profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if browserChromePresentation != nil {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(session.profile.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(session.currentOrigin?.host ?? session.profile.homePageHost)
                            .font(.caption2)
                            .foregroundStyle(AppUI.secondaryText)
                    }
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("groupCheckIn.environment")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("更多", systemImage: "ellipsis.circle") {
                    if let profile = model.profiles.first(where: { $0.id == session.profile.id }) {
                        Text(model.balanceStatus(for: profile) ?? "尚未读取余额")
                    }
                    Button("重新读取余额", systemImage: "arrow.clockwise") {
                        Task { balanceFeedback = await model.refreshBalance(for: session).message }
                    }
                    .disabled(!automaticallyRefreshesBalance || model.isRefreshingBalance(for: session.profile.id))
                    Button("网站识别规则", systemImage: "slider.horizontal.3") { showsWebsiteRules = true }
                        .accessibilityIdentifier("browser.websiteRules")
                    Button("网页诊断", systemImage: "waveform.path.ecg") { showsDiagnostics = true }
                }
                .accessibilityIdentifier("browser.more")
            }
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
            session.requestBalanceRead()
        }
        .onChange(of: session.page.isLoading) { _, loading in
            if !loading { session.requestBalanceRead() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session.requestBalanceRead() }
        }
        .task {
            guard automaticallyRefreshesBalance else { return }
            for await _ in session.balanceReadRequests() {
                guard !Task.isCancelled else { return }
                await model.refreshBalance(for: session)
            }
        }
        .task {
            let currentSession = session
            let appModel = model
            let eventObserver = onAutomationEvent
            model.markOpened(session.profile)
            session.configureAutomation(
                settings: automationSettings ?? model.globalScriptSettings,
                shouldRunToday: model.shouldRunAutomation(for: session.profile.id),
                completionKey: model.automationCompletionKey(for: session.profile.id)
            ) { [weak currentSession] event in
                guard let currentSession else { return }
                guard appModel.profiles.first(where: { $0.id == currentSession.profile.id })?.accountScopeKey == currentSession.profile.accountScopeKey else { return }
                appModel.handleAutomationEvent(event, for: currentSession.profile.id)
                eventObserver?(currentSession.profile.id, event)
                if event.kind == .success, eventObserver == nil {
                    Task { await appModel.refreshBalance(for: currentSession, afterCheckIn: true) }
                }
            }
            session.start()
            session.requestBalanceRead()
        }
        .sheet(isPresented: $showsWebsiteRules) {
            NavigationStack { WebsiteRulesView(session: session) }
        }
        .alert("余额读取结果", isPresented: Binding(get: { balanceFeedback != nil }, set: { if !$0 { balanceFeedback = nil } })) {
            Button("好", role: .cancel) { balanceFeedback = nil }
        } message: { Text(balanceFeedback ?? "") }
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
        .onDisappear { if browserChromePresentation == nil { session.close() } }
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

    private var browserChromeBinding: Binding<Bool> {
        browserChromePresentation ?? $showsBrowserChrome
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { session.presentedError != nil },
            set: { if !$0 { session.presentedError = nil } }
        )
    }
}

@MainActor
private struct AutomationStatusBanner: View {
    let state: AutomationState
    let message: String
    let resume: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.related) {
            AppStatusMessage(message: message, tone: tone, symbol: iconName)
            if state == .captcha {
                Button(action: resume) {
                    Label("继续检测", systemImage: "arrow.clockwise")
                }
                .buttonStyle(WorkspaceActionStyle(prominent: true))
                .accessibilityHint("在网页上手动完成验证后继续检测")
            }
        }
        .padding(.horizontal, AppUI.Spacing.page)
        .padding(.vertical, AppUI.Spacing.related)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityElement(children: .contain)
    }

    private var iconName: String {
        switch state {
        case .success: "checkmark.circle"
        case .captcha: "hand.raised"
        case .error: "exclamationmark.triangle"
        case .noButton: "questionmark.circle"
        case .skipped: "clock.arrow.circlepath"
        case .running: "arrow.triangle.2.circlepath"
        case .inactive: "info.circle"
        }
    }

    private var tone: AppStatusMessage.Tone {
        switch state {
        case .success: .success
        case .captcha, .noButton: .warning
        case .error: .error
        case .skipped, .running, .inactive: .neutral
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
        .background(Color(uiColor: .systemGroupedBackground))
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
                    .foregroundStyle(session.currentOrigin?.isSecure == true ? AppUI.success : AppUI.secondaryText)
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

                Button {
                    session.reloadOrStop()
                } label: {
                    Label(
                        session.page.isLoading ? "停止载入" : "重新载入",
                        systemImage: session.page.isLoading ? "xmark" : "arrow.clockwise"
                    )
                    .modifier(BrowserControlLabel())
                }
                .buttonStyle(WorkspaceRowButtonStyle())
            }
            .padding(.leading, 12)
            .background { ControlGlass(cornerRadius: 22).allowsHitTesting(false).accessibilityHidden(true) }

            Button {
                hideChrome()
            } label: {
                Label("隐藏浏览器工具栏", systemImage: "chevron.down")
                    .modifier(BrowserControlLabel())
            }
            .buttonStyle(WorkspaceRowButtonStyle())
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
            toolbarButton("网页诊断", systemImage: "waveform.path.ecg", action: showDiagnostics)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
    }

    private func toolbarButton(
        _ label: String,
        systemImage: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .modifier(BrowserControlLabel())
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
    }
}

private struct BrowserControlLabel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .labelStyle(.iconOnly)
            .frame(minWidth: AppUI.minimumTarget, minHeight: AppUI.minimumTarget)
            .contentShape(Rectangle())
    }
}
