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

    private var hasStarted = false
    private let proxyConfigurationError: String?

    init(profile: BrowserProfile, socksProxy: SocksProxy? = nil) {
        self.profile = profile
        self.socksProxy = socksProxy
        self.addressText = profile.homePage.absoluteString

        let dataStore = WKWebsiteDataStore(forIdentifier: profile.websiteDataStoreID)
        self.dataStore = dataStore

        var proxyConfigurationError: String?
        if let socksProxy, let endpoint = Self.endpoint(for: socksProxy) {
            var proxyConfiguration = ProxyConfiguration(socksv5Proxy: endpoint)
            // An empty match domain is Network's default-domain wildcard.
            // Without it WebKit may leave ordinary page requests outside the
            // proxy configuration, depending on the OS release.
            proxyConfiguration.matchDomains = [""]
            proxyConfiguration.excludedDomains = []
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
        configuration.userContentController = WKUserContentController()
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
        page.load(url)
    }

    func syncAddressBar(with url: URL?) {
        guard let url else { return }
        addressText = url.absoluteString
    }

    func goBack() {
        guard let item = page.backForwardList.backList.last else { return }
        page.load(item)
    }

    func goForward() {
        guard let item = page.backForwardList.forwardList.first else { return }
        page.load(item)
    }

    func goHome() {
        navigate(to: profile.homePage)
    }

    func reloadOrStop() {
        if page.isLoading {
            page.stopLoading()
        } else {
            page.reload()
        }
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
