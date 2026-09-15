import Foundation
import Network
import Observation
import WebKit

@MainActor
@Observable
final class BrowserSession {
    let profile: BrowserProfile
    let socksProxy: SocksProxy?
    let dataStore: WKWebsiteDataStore
    let page: WebPage

    var addressText: String
    var presentedError: PresentedError?
    private(set) var automationState: AutomationState = .inactive
    private(set) var automationMessage: String?

    private var hasStarted = false
    private var navigationTask: Task<Void, Never>?
    private var navigationGeneration = 0
    private let proxyConfigurationError: String?
    private let userContentController: WKUserContentController
    private var automationMessageHandler: AutomationMessageHandler?
    private var automationConfigured = false
    private var automationPaused = false
    private var automationEventHandler: (@MainActor (AutomationEvent) -> Void)?

    init(profile: BrowserProfile, socksProxy: SocksProxy? = nil) {
        self.profile = profile
        self.socksProxy = socksProxy
        self.addressText = profile.homePage.absoluteString

        let dataStore = WKWebsiteDataStore(forIdentifier: profile.websiteDataStoreID)
        self.dataStore = dataStore

        var proxyConfigurationError: String?
        if let socksProxy, let endpoint = Self.endpoint(for: socksProxy) {
            var proxyConfiguration = ProxyConfiguration(socksv5Proxy: endpoint)
            // Never fall back to a direct connection if the selected proxy
            // fails. That would expose the environment's real network path.
            proxyConfiguration.allowFailover = false
            if let username = socksProxy.username,
               let password = socksProxy.password {
                proxyConfiguration.applyCredential(username: username, password: password)
            }
            dataStore.proxyConfigurations = [proxyConfiguration]
        } else {
            dataStore.proxyConfigurations = []
            if socksProxy != nil {
                proxyConfigurationError = "SOCKS 代理地址无效，无法打开环境。"
            } else if let proxyNumber = profile.socksProxyNumber {
                // A profile that explicitly selected a proxy must never
                // silently fall back to a direct connection when that volatile
                // number is temporarily missing.
                proxyConfigurationError = "当前没有第 \(proxyNumber) 号 SOCKS 代理，无法直连打开环境。"
            } else {
                proxyConfigurationError = nil
            }
        }

        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = dataStore
        let userContentController = WKUserContentController()
        configuration.userContentController = userContentController
        configuration.upgradeKnownHostsToHTTPS = true
        configuration.deviceSensorAuthorization = WebPage.DeviceSensorAuthorization(decision: .deny)

        let page = WebPage(configuration: configuration)
        page.customUserAgent = profile.userAgent
#if DEBUG
        page.isInspectable = true
#else
        page.isInspectable = false
#endif
        self.page = page
        self.proxyConfigurationError = proxyConfigurationError
        self.userContentController = userContentController
    }

    private static func endpoint(for proxy: SocksProxy) -> NWEndpoint? {
        let host = SocksProxy.normalizeHost(proxy.host)
        guard (1...65_535).contains(proxy.port),
              let port = NWEndpoint.Port(rawValue: UInt16(proxy.port)),
              !host.isEmpty,
              host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              !host.contains(where: { "/?#".contains($0) }) else {
            return nil
        }
        return .hostPort(host: NWEndpoint.Host(host), port: port)
    }

    var canGoBack: Bool { !page.backForwardList.backList.isEmpty }
    var canGoForward: Bool { !page.backForwardList.forwardList.isEmpty }
    var currentOrigin: WebOrigin? { page.url.flatMap(WebOrigin.init(url:)) }

    /// Adds the global userscript before the first navigation. A script is
    /// never attached to a session that has not explicitly entered an
    /// environment, preserving the app's no-network-before-entry rule.
    func configureAutomation(
        settings: GlobalScriptSettings,
        shouldRunToday: Bool,
        completionKey: String,
        onEvent: (@MainActor (AutomationEvent) -> Void)? = nil
    ) {
        guard !automationConfigured else { return }
        automationConfigured = true
        automationEventHandler = onEvent

        guard settings.enabled else {
            automationState = .inactive
            return
        }

        let parsed = AutomationScriptParser.parse(settings.source)
        guard !parsed.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            automationState = .error
            automationMessage = "全局签到脚本为空，已跳过自动执行。"
            return
        }

        guard shouldRunToday else {
            automationState = .skipped
            automationMessage = "今天已完成签到，已跳过自动执行。"
            return
        }

        let handler = AutomationMessageHandler(session: self)
        userContentController.add(handler, name: AutomationBridge.messageName)
        automationMessageHandler = handler

        let source = AutomationScriptBuilder.build(
            code: parsed.source,
            matches: parsed.matches,
            completionKey: completionKey
        )
        let injectionTime: WKUserScriptInjectionTime = parsed.runsAtDocumentStart
            ? .atDocumentStart
            : .atDocumentEnd
        userContentController.addUserScript(
            WKUserScript(
                source: source,
                injectionTime: injectionTime,
                forMainFrameOnly: true
            )
        )
        automationState = .running
    }

    func resumeAutomation() async {
        guard automationConfigured else { return }
        automationPaused = false
        automationState = .running
        automationMessage = nil
        _ = try? await page.callJavaScript(
            "window.CwebCheckIn && window.CwebCheckIn.resume && window.CwebCheckIn.resume(); true",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
    }

    func receiveAutomationMessage(type: String, message: String) {
        guard let kind = AutomationEventKind(rawValue: type) else { return }
        let event = AutomationEvent(kind: kind, message: message)

        switch kind {
        case .success:
            guard !automationPaused else { return }
            automationState = .success
            automationMessage = message.isEmpty ? "签到成功，今天不再重复执行。" : message
        case .captcha:
            automationPaused = true
            automationState = .captcha
            automationMessage = message.isEmpty ? "检测到验证码，请手动完成。" : message
        case .noButton:
            automationState = .noButton
            automationMessage = message.isEmpty ? "未找到签到入口。" : message
        case .error:
            automationState = .error
            automationMessage = message.isEmpty ? "签到脚本运行失败。" : message
        case .resume:
            automationPaused = false
            automationState = .running
            automationMessage = nil
        }

        automationEventHandler?(event)
    }

    func start() {
        guard !hasStarted else { return }
        if let proxyConfigurationError {
            presentedError = PresentedError(message: proxyConfigurationError)
            hasStarted = true
            return
        }
        hasStarted = true
        navigate(to: profile.homePage)
    }

    /// Creates a document for diagnostics without loading the profile's home
    /// page. The same isolated data store, User-Agent, and SOCKS configuration
    /// are retained, including the no-direct-failover policy.
    func prepareForNetworkDiagnostics() async throws {
        if let proxyConfigurationError {
            throw BrowserSessionDiagnosticError(message: proxyConfigurationError)
        }

        do {
            for try await _ in page.load(URL(string: "about:blank")!) { }
        } catch {
            throw BrowserSessionDiagnosticError(
                message: Self.navigationErrorMessage(error)
            )
        }
    }

    func navigateFromAddressBar() {
        guard let url = Self.resolveAddress(addressText) else {
            presentedError = PresentedError(message: "请输入有效的网址或搜索内容。")
            return
        }
        navigate(to: url)
    }

    func navigate(to url: URL) {
        guard proxyConfigurationError == nil else {
            if let proxyConfigurationError {
                presentedError = PresentedError(message: proxyConfigurationError)
            }
            return
        }
        addressText = url.absoluteString
        startNavigation { page.load(url) }
    }

    func syncAddressBar(with url: URL?) {
        guard let url else { return }
        addressText = url.absoluteString
    }

    func goBack() {
        guard let item = page.backForwardList.backList.last else { return }
        startNavigation { page.load(item) }
    }

    func goForward() {
        guard let item = page.backForwardList.forwardList.first else { return }
        startNavigation { page.load(item) }
    }

    func goHome() {
        navigate(to: profile.homePage)
    }

    func reloadOrStop() {
        if page.isLoading {
            navigationTask?.cancel()
            navigationTask = nil
            navigationGeneration += 1
            page.stopLoading()
        } else {
            startNavigation { page.reload() }
        }
    }

    /// Starts a WebPage navigation and observes the sequence it returns.
    /// Discarding this sequence hides the underlying proxy, DNS, TLS, and
    /// connection errors, leaving the user with a blank page. Keeping one task
    /// per active navigation also ensures a cancelled/previous load cannot
    /// surface an error after a newer navigation has begun.
    private func startNavigation<S: AsyncSequence>(
        _ makeSequence: () -> S
    ) where S.Element == WebPage.NavigationEvent {
        navigationTask?.cancel()
        navigationTask = nil
        navigationGeneration += 1
        let generation = navigationGeneration
        // Evaluate the loading API only after cancelling the previous task.
        // WebPage stops its current load when the task observing the previous
        // sequence is cancelled; reversing this order could stop the new load.
        let sequence = makeSequence()

        navigationTask = Task { @MainActor [weak self] in
            do {
                for try await _ in sequence { }
            } catch {
                guard !Task.isCancelled,
                      let self,
                      self.navigationGeneration == generation else { return }
                self.presentedError = PresentedError(
                    message: Self.navigationErrorMessage(error)
                )
            }

            guard let self,
                  self.navigationGeneration == generation else { return }
            self.navigationTask = nil
        }
    }

    private static func navigationErrorMessage(_ error: Error) -> String {
        if let navigationError = error as? WebPage.NavigationError {
            switch navigationError {
            case .failedProvisionalNavigation(let underlyingError):
                let detail = Self.networkErrorDetail(underlyingError)
                return detail.isEmpty ? "页面加载失败，请检查代理和网络连接。" : "页面加载失败：\(detail)"
            case .invalidURL:
                return "页面地址无效。"
            case .pageClosed:
                return "页面已关闭，无法继续加载。"
            case .webContentProcessTerminated:
                return "网页进程已终止，请重试。"
            @unknown default:
                return "页面加载失败，请检查代理和网络连接。"
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return "网络请求失败：\(Self.networkErrorDetail(error))"
        }
        let detail = error.localizedDescription
        return detail.isEmpty ? "页面加载失败，请检查代理和网络连接。" : detail
    }

    private static func networkErrorDetail(_ error: Error) -> String {
        let nsError = error as NSError
        let description = nsError.localizedDescription
        guard nsError.domain == NSURLErrorDomain else { return description }
        let code = nsError.code
        return description.isEmpty
            ? "\(nsError.domain) \(code)"
            : "\(description)（\(nsError.domain) \(code)）"
    }

    func fill(_ credential: StoredCredential) async throws -> CredentialFillResult {
        guard currentOrigin == credential.origin else {
            throw CredentialFillError.originChanged
        }

        let functionBody = """
        const setValue = (element, value) => {
            if (!element) return false;
            const descriptor = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
            descriptor.set.call(element, value);
            element.dispatchEvent(new Event('input', { bubbles: true }));
            element.dispatchEvent(new Event('change', { bubbles: true }));
            return true;
        };

        const passwordInput = document.querySelector('input[type="password"]');
        const usernameInput = document.querySelector(
            'input[autocomplete="username"], input[type="email"], input[name*="user" i], input[type="text"]'
        );

        return {
            usernameFilled: setValue(usernameInput, username),
            passwordFilled: setValue(passwordInput, password)
        };
        """

        let value = try await page.callJavaScript(
            functionBody,
            arguments: [
                "username": credential.username,
                "password": credential.password
            ],
            in: nil,
            contentWorld: .page
        )
        let result = value as? [String: Any]
        return CredentialFillResult(
            usernameFilled: result?["usernameFilled"] as? Bool ?? false,
            passwordFilled: result?["passwordFilled"] as? Bool ?? false
        )
    }

    func readAccountBalance() async throws -> String? {
        let functionBody = """
        const element = [...document.querySelectorAll('div')].find((node) => {
            const classes = node.classList;
            return classes.contains('text-foreground')
                && classes.contains('mt-1.5')
                && classes.contains('font-mono')
                && classes.contains('text-lg')
                && classes.contains('font-bold')
                && classes.contains('tracking-tight')
                && classes.contains('tabular-nums');
        });
        return element?.textContent?.trim() || null;
        """

        let value = try await page.callJavaScript(
            functionBody,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        guard let balance = value as? String else { return nil }
        let trimmed = balance.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func resolveAddress(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if
            let directURL = URL(string: trimmed),
            let scheme = directURL.scheme?.lowercased(),
            (scheme == "https" || scheme == "http"),
            directURL.host != nil
        {
            return directURL
        }

        if !trimmed.contains(where: { $0.isWhitespace }),
           let httpsURL = URL(string: "https://\(trimmed)"),
           httpsURL.host != nil {
            return httpsURL
        }

        var components = URLComponents(string: "https://duckduckgo.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return components?.url
    }
}

struct CredentialFillResult {
    let usernameFilled: Bool
    let passwordFilled: Bool
}

enum CredentialFillError: LocalizedError {
    case originChanged

    var errorDescription: String? {
        "页面地址已经变化，请重新选择凭据。"
    }
}

struct BrowserSessionDiagnosticError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}
