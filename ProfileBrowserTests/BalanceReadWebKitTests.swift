import Foundation
import Network
import SwiftUI
import Testing
import UIKit
import WebKit
@testable import ProfileBrowser

@MainActor
@Suite(.serialized)
struct BalanceReadWebKitTests {
    private static let amountClass = "text-foreground mt-1.5 font-mono text-lg font-bold tracking-tight tabular-nums"

    @Test
    func legacyDashboardSelectsTheBalanceAmongOtherAmountCards() async throws {
        let session = BrowserSession(profile: BrowserProfile(name: "余额回归"))
        defer { session.close() }
        try await load("""
        <section><span>累计消费</span><div class="\(Self.amountClass)">$3.00</div></section>
        <section><span>当前余额</span><div class="\(Self.amountClass)">$12.50</div></section>
        <section><span>累计充值</span><div class="\(Self.amountClass)">$20.00</div></section>
        """, in: session)
        #expect(try await session.readAccountBalance() == "$12.50")
        #expect(try await session.readAccountBalanceResult()?.sourceVerified == true)
    }

    @Test
    func legacyMarkupWithoutLabelsKeepsItsOriginalFirstAmountBehavior() async throws {
        let session = BrowserSession(profile: BrowserProfile(name: "兼容旧页面"))
        defer { session.close() }
        try await load("""
        <div class="\(Self.amountClass)">$12.50</div>
        <div class="\(Self.amountClass)">$3.00</div>
        """, in: session)
        #expect(try await session.readAccountBalance() == "$12.50")
        #expect(try await session.readAccountBalanceResult()?.sourceVerified == false)
    }

    @Test
    func juAPIDashboardReadsTheLabeledBalanceInsteadOfConsumptionOrStatistics() async throws {
        let session = BrowserSession(profile: BrowserProfile(name: "JuAPI 页面结构"))
        defer { session.close() }
        // The label/value structure observed on cdn.juaiapi.com/console.
        // Amounts are synthetic; no account data is stored in this fixture.
        try await load("""
        <div class="dashboard-stat-copy"><div class="dashboard-stat-label">历史消耗</div><div class="dashboard-stat-value">$90.00</div></div>
        <div class="dashboard-stat-item"><div class="dashboard-stat-detail">
          <span aria-hidden="true">图标</span><div class="dashboard-stat-copy">
            <div class="dashboard-stat-label">当前余额</div><div class="dashboard-stat-value">$12.50</div>
          </div></div><div role="button">充值</div></div>
        <div class="dashboard-stat-copy"><div class="dashboard-stat-label">请求次数</div><div class="dashboard-stat-value">4006</div></div>
        <div class="dashboard-stat-copy"><div class="dashboard-stat-label">统计额度</div><div class="dashboard-stat-value">$0.00</div></div>
        """, in: session)
        #expect(try await session.readAccountBalance() == "$12.50")
        #expect(try await session.readAccountBalanceResult()?.sourceVerified == true)
    }

    @Test(arguments: ["semi", "ant"])
    func statisticCardsUseTheirOwnBalanceTitleAndPreserveSplitCurrency(prefix: String) async throws {
        let session = BrowserSession(profile: BrowserProfile(name: "统计卡片"))
        defer { session.close() }
        try await load("""
        <div class="\(prefix)-statistic"><div class="\(prefix)-statistic-title">Used balance</div><div class="\(prefix)-statistic-content">$90.00</div></div>
        <div class="\(prefix)-statistic"><div class="\(prefix)-statistic-title">Available balance</div><div class="\(prefix)-statistic-content"><span>$</span><span>0.00</span></div></div>
        """, in: session)
        #expect(try await session.readAccountBalanceResult() == AccountBalanceReading(value: "$0.00", sourceVerified: true))
    }

    @Test
    func automaticCardsRejectLoadingConflictsAndUnrelatedLabels() async throws {
        let session = BrowserSession(profile: BrowserProfile(name: "余额卡片边界"))
        defer { session.close() }
        let card = "<div class='dashboard-stat-copy'><div class='dashboard-stat-label'>当前余额</div><div class='dashboard-stat-value'>$12.50</div></div>"
        for body in [
            "<div class='dashboard-stat-copy'><div class='dashboard-stat-label'>当前余额</div></div><div class='\(Self.amountClass)'>$99.00</div>",
            "<section aria-busy='true'>\(card)</section>",
            card + card.replacingOccurrences(of: "$12.50", with: "$20.00"),
            card.replacingOccurrences(of: "$12.50", with: "加载中…"),
            card.replacingOccurrences(of: "$12.50", with: "<span role='progressbar'>加载</span>$12.50"),
            card.replacingOccurrences(of: "当前余额", with: "余额变动"),
            card.replacingOccurrences(of: "当前余额", with: "历史余额"),
            card.replacingOccurrences(of: "当前余额", with: "历史消耗")
        ] {
            try await load(body, in: session)
            #expect(try await session.readAccountBalanceResult() == nil)
        }
        try await load(card + card + "<div hidden>\(card.replacingOccurrences(of: "$12.50", with: "$99.00"))</div>", in: session)
        #expect(try await session.readAccountBalanceResult() == AccountBalanceReading(value: "$12.50", sourceVerified: true))
    }

    @Test
    func explicitBalanceRuleDoesNotRequireAnExtraReadySelectorToVerifyItsSource() async throws {
        let session = BrowserSession(profile: BrowserProfile(name: "指定余额来源"))
        defer { session.close() }
        try await load("<div id='my-balance'>$12.50</div>", in: session)
        let rule = WebsiteRule(host: "localhost", balanceSelector: "#my-balance")
        #expect(try await session.readAccountBalanceResult(rule: rule) == AccountBalanceReading(value: "$12.50", sourceVerified: true))
    }

    @Test
    func unrelatedProgressAndIdenticalResponsiveBalancesDoNotBlockReading() async throws {
        let session = BrowserSession(profile: BrowserProfile(name: "响应式页面"))
        defer { session.close() }
        try await load("""
        <aside role="progressbar">图表加载中</aside>
        <div data-account-balance>$12.50</div><div data-account-balance>$12.50</div>
        <div data-account-balance style="visibility:hidden">$99.00</div>
        """, in: session)
        #expect(try await session.readAccountBalance() == "$12.50")
    }

    @Test
    func explicitRulesStillRejectUnreadyBusyAndConflictingAmounts() async throws {
        let session = BrowserSession(profile: BrowserProfile(name: "规则校验"))
        defer { session.close() }
        let rule = WebsiteRule(host: "localhost", balanceSelector: ".balance", balanceReadySelector: "#ready")
        for body in [
            "<div class='balance'>$0.00</div>",
            "<div id='ready'></div><section aria-busy='true'><div class='balance'>$0.00</div></section>",
            "<div id='ready'></div><div class='balance'><span role='progressbar'>加载中</span>$0.00</div>",
            "<div id='ready'></div><div class='balance'>$12.50</div><div class='balance'>$20.00</div>",
            "<div id='ready'></div><div class='balance'>加载中…</div>"
        ] {
            try await load(body, in: session)
            #expect(try await session.readAccountBalance(rule: rule) == nil)
        }
        try await load("<div id='ready'></div><div class='balance'>$0.00</div>", in: session)
        #expect(try await session.readAccountBalance(rule: rule) == "$0.00")
    }

    @Test(arguments: [false, true])
    func manualEntryAndPostCheckInReloadPersistTheFreshBalance(dashboardStyle: Bool) async throws {
        let server = try BalanceHTTPFixture(dashboardStyle: dashboardStyle)
        defer { server.stop() }
        let url = try await server.start()
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let suite = "Cweb.BalanceWebKitTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let profile = BrowserProfile(name: "实际 WebKit 路径", homePage: url, cachedBalance: "$1.00")
        let repository = ProfileRepository(fileURL: directory.appending(path: "profiles.json"))
        try repository.save([profile])
        let model = AppModel(profileRepository: repository, credentialVault: CredentialVault(inMemory: true),
            socksProxyRepository: SocksProxyRepository(fileURL: directory.appending(path: "proxies.json"),
                credentialStore: SocksProxyCredentialStore(inMemory: true)), userDefaults: defaults)
        let session = BrowserSession(profile: profile)
        let host = try BalanceWebKitHost(page: session.page)
        defer { session.close(); host.close() }
        var successes = 0
        session.configureAutomation(settings: GlobalScriptSettings(enabled: true,
            source: "window.CwebCheckIn.success('已完成签到');", updatedAt: .now),
            shouldRunToday: true, completionKey: UUID().uuidString) { event in
                if event.kind == .success { successes += 1 }
            }
        // Exercise the same immediate entry read as BrowserView, while an
        // unrelated subresource keeps document.readyState at interactive.
        session.start()
        await model.refreshBalance(for: session)
        #expect(session.presentedError?.message == nil)
        #expect(model.profiles.first?.cachedBalance == "$12.50")
        #expect(model.profiles.first?.balanceReadError == nil)
        #expect(model.profiles.first?.balanceUpdatedAt != nil)
        let enteredProfile = try #require(model.profiles.first)
        #expect(enteredProfile.balanceSourceVerified == true)
        #expect(model.balanceStatus(for: enteredProfile)?.hasPrefix("更新于 ") == true)
        #expect(successes == 1)
        let state = try await session.page.callJavaScript("return document.readyState;") as? String
        #expect(state == "interactive")

        await model.refreshBalance(for: session, afterCheckIn: true)
        #expect(server.pageRequests == 2)
        #expect(model.profiles.first?.cachedBalance == "$13.00")
        #expect(model.profiles.first?.balanceReadError == nil)
        #expect(try repository.load().first?.cachedBalance == "$13.00")
        #expect(try repository.load().first?.balanceSourceVerified == true)
        #expect(successes == 1) // Reload must not run the check-in script again.
    }

    private func load(_ body: String, in session: BrowserSession) async throws {
        for try await _ in session.page.load(html: "<html><body>" + body + "</body></html>") { }
    }
}

@MainActor
private final class BalanceWebKitHost {
    private let window: UIWindow
    private weak var previousWindow: UIWindow?

    init(page: WebPage) throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        previousWindow = scene.keyWindow
        window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: WebView(page))
        window.makeKeyAndVisible()
    }

    func close() {
        window.isHidden = true
        window.rootViewController = nil
        previousWindow?.makeKeyAndVisible()
    }
}

/// A local HTTP document is necessary to exercise the real origin reload.
/// /pending deliberately never finishes, like a stalled analytics image.
private final class BalanceHTTPFixture: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "Cweb.BalanceHTTPFixture")
    private let lock = NSLock()
    private var requests = 0
    private var connections: [NWConnection] = []
    private let dashboardStyle: Bool
    var pageRequests: Int { lock.withLock { requests } }

    init(dashboardStyle: Bool) throws {
        self.dashboardStyle = dashboardStyle
        listener = try NWListener(using: .tcp, on: .any)
    }

    func start() async throws -> URL {
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.connections.append(connection)
            connection.start(queue: self.queue)
            self.receive(connection, request: Data())
        }
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    guard let self, let port = self.listener.port else { return }
                    self.listener.stateUpdateHandler = nil
                    continuation.resume(returning: URL(string: "http://127.0.0.1:\(port.rawValue)/")!)
                case .failed(let error):
                    self?.listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    private func receive(_ connection: NWConnection, request: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self else { return }
            let request = request + (data ?? Data())
            guard let text = String(data: request, encoding: .utf8), text.contains("\r\n\r\n") else {
                if !complete, error == nil { self.receive(connection, request: request) }
                return
            }
            if text.hasPrefix("GET /pending ") { return }
            guard text.hasPrefix("GET / ") else {
                connection.send(content: Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8),
                    completion: .contentProcessed { _ in connection.cancel() })
                return
            }
            let count = self.lock.withLock { self.requests += 1; return self.requests }
            let balance = count == 1 ? "$12.50" : "$13.00"
            let markup = self.dashboardStyle ? """
            <div class="dashboard-stat-copy"><div class="dashboard-stat-label">历史消耗</div><div class="dashboard-stat-value">$90.00</div></div>
            <div class="dashboard-stat-copy"><div class="dashboard-stat-label">当前余额</div><div class="dashboard-stat-value">\(balance)</div></div>
            <div class="dashboard-stat-copy"><div class="dashboard-stat-label">统计额度</div><div class="dashboard-stat-value">$0.00</div></div>
            """ : "<div data-account-balance>\(balance)</div>"
            let html = """
            <html><body>\(markup)
            <aside role="progressbar">统计图加载中</aside><img src="/pending"></body></html>
            """
            let body = Data(html.utf8)
            let headers = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(headers.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    func stop() {
        listener.cancel()
        queue.sync {
            connections.forEach { $0.cancel() }
            connections.removeAll()
        }
    }
}
