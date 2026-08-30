import Foundation
import Testing
@testable import ProfileBrowser

struct SocksProxyTests {
    @Test
    func parsesAuthenticatedIPv6URLAndRedactsPassword() throws {
        let proxy = try SocksProxy(urlString: "socks5h://user:p%40ss@[2001:db8::1]:1080")

        #expect(proxy.scheme == .socks5h)
        #expect(proxy.host == "2001:db8::1")
        #expect(proxy.port == 1080)
        #expect(proxy.username == "user")
        #expect(proxy.password == "p@ss")
        #expect(proxy.displayAddress == "socks5h://user@[2001:db8::1]:1080")
        #expect(proxy.sourceURLString == proxy.displayAddress)
    }

    @Test
    func parsesFeedAndDeduplicatesByEndpoint() throws {
        let content = """
        # public feed
        socks5://127.0.0.1:1001
        socks://127.0.0.1:1001
        socks5://127.0.0.1:1002
        invalid://host:10
        """

        let proxies = try SocksProxyParser.parseList(content)

        #expect(proxies.count == 2)
        #expect(proxies.map(\.port) == [1001, 1002])
    }

    @Test
    func rejectsUnsupportedAndInvalidPorts() {
        #expect(throws: SocksProxyParseError.unsupportedScheme) {
            _ = try SocksProxy(urlString: "http://127.0.0.1:1080")
        }
        #expect(throws: SocksProxyParseError.invalidPort) {
            _ = try SocksProxy(urlString: "socks5://127.0.0.1:65536")
        }
    }

    @Test
    func repositoryRoundTripsRecordsAndKeepsPasswordOutOfJSON() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let fileURL = directory.appending(path: "proxies.json")
        let presetsURL = directory.appending(path: "presets.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let credentialStore = SocksProxyCredentialStore(inMemory: true)
        let repository = SocksProxyRepository(
            fileURL: fileURL,
            presetsFileURL: presetsURL,
            credentialStore: credentialStore
        )
        let proxy = try SocksProxy(urlString: "socks5://alice:secret@127.0.0.1:1080")
        try repository.save([proxy])

        let loaded = try repository.load()
        #expect(loaded == [proxy])
        let rawJSON = try String(contentsOf: fileURL)
        #expect(!rawJSON.contains("secret"))

        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let presets = [
            SocksProxyPreset(
                name: "主订阅",
                url: try #require(URL(string: "https://example.com/a")),
                createdAt: timestamp,
                updatedAt: timestamp
            ),
            SocksProxyPreset(
                name: "备用订阅",
                url: try #require(URL(string: "https://example.com/b")),
                createdAt: timestamp,
                updatedAt: timestamp
            )
        ]
        try repository.savePresets(presets)
        #expect(try repository.loadPresets() == presets)

        try repository.removeAll()
        #expect(try repository.load().isEmpty)
        #expect(try credentialStore.password(for: proxy.id) == nil)
    }

    @Test
    func importingSameEndpointRefreshesRotatedCredentials() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let fileURL = directory.appending(path: "proxies.json")
        let credentialStore = SocksProxyCredentialStore(inMemory: true)
        let repository = SocksProxyRepository(fileURL: fileURL, credentialStore: credentialStore)
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = try SocksProxy(urlString: "socks5://user:old@127.0.0.1:1080")
        try repository.save([original])
        let refreshed = try SocksProxy(urlString: "socks5://user:new@127.0.0.1:1080")

        let values = try repository.appendUnique([refreshed])

        #expect(values.count == 1)
        #expect(values[0].id == original.id)
        #expect(values[0].password == "new")
        #expect(values[0].status == .untested)
    }

    @Test
    func refreshedFeedReplacesEndpointInPlace() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let fileURL = directory.appending(path: "proxies.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = SocksProxyRepository(
            fileURL: fileURL,
            credentialStore: SocksProxyCredentialStore(inMemory: true)
        )
        let original = try SocksProxy(urlString: "socks5://alice:old@127.0.0.1:1080")
        try repository.save([original])
        let refreshed = try SocksProxy(urlString: "socks5://alice:new@127.0.0.1:1080")

        let merged = try repository.mergeRefreshing([refreshed])

        #expect(merged.count == 1)
        #expect(merged[0].id == original.id)
        #expect(try repository.load()[0].password == "new")
    }

    @Test
    func validationSortsAvailableByLatencyAndRetainsStableTieOrder() async {
        let first = SocksProxy(host: "one.example", port: 1080)
        let second = SocksProxy(host: "two.example", port: 1080)
        let third = SocksProxy(host: "three.example", port: 1080)
        let unavailable = SocksProxyProbeResult(status: .unavailable, message: "offline")
        let probe = StubProbe(results: [
            first.id: SocksProxyProbeResult(status: .available, latencyMilliseconds: 80),
            second.id: SocksProxyProbeResult(status: .available, latencyMilliseconds: 20),
            third.id: SocksProxyProbeResult(status: .available, latencyMilliseconds: 20),
            // Keep one failed result to ensure unavailable values are placed last.
            UUID(): unavailable
        ])

        let service = SocksProxyValidationService(timeout: 1, probe: probe)
        let sorted = await service.validateAndSort([first, second, third])

        #expect(sorted.map(\.id) == [second.id, third.id, first.id])
        #expect(sorted.map(\.latencyMilliseconds) == [20, 20, 80])
        #expect(sorted.allSatisfy { $0.status == .available })
        #expect(SocksProxyValidationService.ranked(sorted).map(\.number) == [1, 2, 3])
        #expect(SocksProxyValidationService.proxy(forDisplayNumber: 1, in: sorted)?.id == second.id)
        #expect(SocksProxyValidationService.proxy(forDisplayNumber: 0, in: sorted) == nil)
    }
}

private struct StubProbe: SocksProxyProbe {
    let results: [UUID: SocksProxyProbeResult]

    func probe(_ proxy: SocksProxy, timeout: TimeInterval) async throws -> SocksProxyProbeResult {
        results[proxy.id] ?? SocksProxyProbeResult(status: .unavailable, message: "missing result")
    }
}
