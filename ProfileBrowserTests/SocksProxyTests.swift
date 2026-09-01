import Foundation
import Testing
@testable import ProfileBrowser

struct SocksProxyTests {
    @Test
    func legacyRecordWithoutLockFieldDefaultsToUnlocked() throws {
        let id = UUID()
        let data = Data(
            """
            {
              "id": "\(id.uuidString)",
              "host": "legacy.example",
              "port": 1080
            }
            """.utf8
        )

        let proxy = try JSONDecoder().decode(SocksProxy.self, from: data)

        #expect(!proxy.isLocked)
    }

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
    func normalizesBracketedIPv6HostForStorageAndDisplay() throws {
        let proxy = SocksProxy(
            code: "  香港主力  ",
            host: " [2001:db8::1] ",
            port: 1080
        )

        #expect(proxy.displayCode == "香港主力")
        #expect(proxy.host == "2001:db8::1")
        #expect(proxy.displayAddress == "socks5://[2001:db8::1]:1080")
        #expect(proxy.identityKey == "2001:db8::1|1080|")
    }

    @Test
    func decodesLegacyRecordWithoutCode() throws {
        let id = UUID()
        let data = Data(
            """
            {
              "id": "\(id.uuidString)",
              "host": "127.0.0.1",
              "port": 1080
            }
            """.utf8
        )

        let proxy = try JSONDecoder().decode(SocksProxy.self, from: data)

        #expect(proxy.id == id)
        #expect(proxy.displayCode == nil)
        #expect(proxy.scheme == .socks5)
        #expect(proxy.status == .untested)
    }

    @Test
    func validationDefaultsToHTTPSConnectProbe() {
        let configuration = SocksProxyValidationConfiguration()

        #expect(configuration.targetURL?.absoluteString == "https://example.com/")
        #expect(configuration.verifiesTLS)
    }

    @Test
    func validationSettingsNormalizeAndRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let proxyURL = directory.appending(path: "proxies.json")
        let settingsURL = directory.appending(path: "settings.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = SocksProxyRepository(
            fileURL: proxyURL,
            settingsFileURL: settingsURL,
            credentialStore: SocksProxyCredentialStore(inMemory: true)
        )
        let input = SocksProxyValidationSettings(
            retainOnlyAvailable: false,
            maxRetainedCount: -10,
            sortMode: .inputOrder,
            targetURLString: " https://www.gstatic.com/generate_204 ",
            verifiesTLS: false,
            timeoutSeconds: 90,
            maxConcurrent: 0
        )

        try repository.saveSettings(input)
        let loaded = try repository.loadSettings()

        #expect(loaded.retainOnlyAvailable == false)
        #expect(loaded.maxRetainedCount == 0)
        #expect(loaded.sortMode == .inputOrder)
        #expect(loaded.targetURLString == "https://www.gstatic.com/generate_204")
        #expect(loaded.validationConfiguration.targetURL?.host == "www.gstatic.com")
        #expect(loaded.validationConfiguration.targetURL?.path == "/generate_204")
        #expect(loaded.verifiesTLS == false)
        #expect(loaded.timeoutSeconds == 60)
        #expect(loaded.maxConcurrent == 1)
        #expect(SocksProxyValidationSettings.targetURL(from: "http://example.com/") == nil)
    }

    @Test
    func legacyValidationTargetMigratesHostAndPortToURL() throws {
        let data = Data(
            """
            {
              "targetHost": "legacy.example",
              "targetPort": 8443
            }
            """.utf8
        )

        let settings = try JSONDecoder().decode(SocksProxyValidationSettings.self, from: data)

        #expect(settings.normalized.targetURLString == "https://legacy.example:8443/")
    }

    @Test
    func staleValidationIsInvalidatedAfterProbeProtocolUpgrade() {
        var proxy = SocksProxy(
            host: "127.0.0.1",
            port: 1080,
            latencyMilliseconds: 12,
            status: .available,
            lastCheckedAt: .now,
            validationMessage: nil,
            validationRevision: 1
        )

        proxy = proxy.invalidatingValidation()

        #expect(proxy.status == .untested)
        #expect(proxy.latencyMilliseconds == nil)
        #expect(proxy.lastCheckedAt == nil)
        #expect(proxy.validationRevision == SocksProxy.currentValidationRevision)
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
        var proxy = try SocksProxy(urlString: "socks5://alice:secret@127.0.0.1:1080")
        proxy.code = "主力 VPS"
        proxy.isLocked = true
        try repository.save([proxy])

        let loaded = try repository.load()
        #expect(loaded == [proxy])
        #expect(loaded[0].displayCode == "主力 VPS")
        #expect(loaded[0].isLocked)
        let rawData = try Data(contentsOf: fileURL)
        let rawJSON = String(decoding: rawData, as: UTF8.self)
        #expect(!rawJSON.contains("secret"))
        let rawRecords = try #require(
            JSONSerialization.jsonObject(with: rawData) as? [[String: Any]]
        )
        #expect(rawRecords[0]["isLocked"] as? Bool == true)

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

        var original = try SocksProxy(urlString: "socks5://user:old@127.0.0.1:1080")
        original.code = "固定代号"
        original.isLocked = true
        try repository.save([original])
        let refreshed = try SocksProxy(urlString: "socks5://user:new@127.0.0.1:1080")

        let values = try repository.appendUnique([refreshed])

        #expect(values.count == 1)
        #expect(values[0].id == original.id)
        #expect(values[0].displayCode == "固定代号")
        #expect(values[0].isLocked)
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
        var original = try SocksProxy(urlString: "socks5://alice:old@127.0.0.1:1080")
        original.code = "备用节点"
        original.isLocked = true
        try repository.save([original])
        let refreshed = try SocksProxy(urlString: "socks5://alice:new@127.0.0.1:1080")

        let merged = try repository.mergeRefreshing([refreshed])

        #expect(merged.count == 1)
        #expect(merged[0].id == original.id)
        #expect(merged[0].displayCode == "备用节点")
        #expect(merged[0].isLocked)
        #expect(try repository.load()[0].password == "new")
    }

    @Test
    func validationSortsAvailableByLatencyAndRetainsStableTieOrder() async {
        let first = SocksProxy(host: "one.example", port: 1080)
        let second = SocksProxy(host: "two.example", port: 1080)
        let third = SocksProxy(host: "three.example", port: 1080)
        let fourth = SocksProxy(host: "four.example", port: 1080)
        let probe = StubProbe(results: [
            first.id: SocksProxyProbeResult(status: .available, latencyMilliseconds: 80),
            second.id: SocksProxyProbeResult(status: .available, latencyMilliseconds: 20),
            third.id: SocksProxyProbeResult(status: .available, latencyMilliseconds: 20),
            // Keep one failed result to ensure unavailable values are placed last.
            fourth.id: SocksProxyProbeResult(status: .unavailable, message: "offline")
        ])

        let service = SocksProxyValidationService(timeout: 1, probe: probe)
        let sorted = await service.validateAndSort([first, second, third, fourth])

        #expect(sorted.map(\.id) == [second.id, third.id, first.id, fourth.id])
        #expect(sorted.prefix(3).compactMap(\.latencyMilliseconds) == [20, 20, 80])
        #expect(sorted.last?.status == .unavailable)
        #expect(SocksProxyValidationService.ranked(sorted).map(\.number) == [1, 2, 3, 4])
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
