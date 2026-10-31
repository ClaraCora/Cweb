import Foundation
import Testing
@testable import ProfileBrowser

@MainActor
struct GroupProxyLatencyTests {
    @Test
    func measuresOnlyDistinctGroupProxiesWithoutChangingBindingsOrRetention() async throws {
        let proxies = (1...3).map {
            SocksProxy(host: "proxy\($0).example", port: 1080, latencyMilliseconds: $0 * 10, status: .available)
        }
        let probe = GroupLatencyProbe(results: [
            proxies[0].id: .init(status: .available, latencyMilliseconds: 900),
            proxies[1].id: .init(status: .unavailable, message: "offline")
        ])
        let fixture = try GroupProxyFixture(proxies: proxies, probe: probe)
        defer { fixture.cleanUp() }
        let model = fixture.model
        try model.updateSocksProxyValidationSettings(
            SocksProxyValidationSettings(retainOnlyAvailable: true, maxRetainedCount: 1)
        )
        let profiles = [1, 2, 1, 999].map {
            BrowserProfile(name: "代理 \($0)", socksProxyNumber: $0)
        } + [BrowserProfile(name: "直连")]
        let bindingsBefore = profiles.map { model.socksProxy(for: $0)?.id }
        let numbersBefore = model.rankedSocksProxies.map(\.proxy.id)
        let results = try await model.validateGroupProxyLatencies(for: profiles)

        let calls = await probe.calls
        #expect(calls.count == 2)
        #expect(Set(calls) == Set(proxies.prefix(2).map(\.id)))
        #expect(results.count == 2)
        #expect(model.socksProxies.count == 3) // Unavailable proxies are retained.
        #expect(model.socksProxies.map(\.status) == [.available, .available, .available])
        #expect(model.socksProxies.map(\.latencyMilliseconds) == [10, 20, 30])
        #expect(model.socksProxies[0].lastLatencyCheck?.latencyMilliseconds == 900)
        #expect(model.socksProxies[1].lastLatencyCheck?.status == .unavailable)
        #expect(model.socksProxies[2].lastLatencyCheck == nil)
        #expect(model.rankedSocksProxies.map(\.proxy.id) == numbersBefore)
        #expect(profiles.map { model.socksProxy(for: $0)?.id } == bindingsBefore)
        let reloaded = try fixture.proxyRepository.load()
        #expect(reloaded.map(\.id) == model.socksProxies.map(\.id))
        #expect(reloaded.map { $0.lastLatencyCheck?.latencyMilliseconds }
            == model.socksProxies.map { $0.lastLatencyCheck?.latencyMilliseconds })
        #expect(reloaded.map { $0.lastLatencyCheck?.status } == [.available, .unavailable, nil])
        let restarted = AppModel(
            profileRepository: fixture.profileRepository,
            socksProxyRepository: fixture.proxyRepository,
            userDefaults: fixture.defaults
        )
        #expect(restarted.socksProxies == reloaded)
        #expect(restarted.rankedSocksProxies.map(\.proxy.id) == numbersBefore)
    }

    @Test
    func editedCredentialsAndChangedProbeRulesInvalidateGroupMeasurement() async throws {
        let proxy = SocksProxy(host: "proxy.example", port: 1080)
        let probe = GroupLatencyProbe(results: [proxy.id: .init(status: .available, latencyMilliseconds: 100)])
        let fixture = try GroupProxyFixture(proxies: [proxy], probe: probe)
        defer { fixture.cleanUp() }
        let profile = BrowserProfile(name: "环境", socksProxyNumber: 1)
        _ = try await fixture.model.validateGroupProxyLatencies(for: [profile])
        #expect(fixture.model.socksProxies[0].lastLatencyCheck != nil)
        var changed = fixture.model.socksProxies[0]
        changed.password = "changed"
        try fixture.model.updateSocksProxy(changed)
        #expect(fixture.model.socksProxies[0].lastLatencyCheck == nil)
        _ = try await fixture.model.validateGroupProxyLatencies(for: [profile])
        var settings = fixture.model.socksProxyValidationSettings
        settings.verifiesTLS.toggle()
        try fixture.model.updateSocksProxyValidationSettings(settings)
        #expect(fixture.model.socksProxies[0].lastLatencyCheck == nil)
        #expect(try fixture.proxyRepository.load()[0].lastLatencyCheck == nil)
    }

    @Test
    func lateMeasurementCannotRestoreResultsForEditedProxy() async throws {
        let proxy = SocksProxy(host: "proxy.example", port: 1080)
        let probe = GatedGroupLatencyProbe()
        let fixture = try GroupProxyFixture(proxies: [proxy], probe: probe)
        defer { fixture.cleanUp() }
        let model = fixture.model
        let task = Task {
            try await model.validateGroupProxyLatencies(for: [BrowserProfile(name: "环境", socksProxyNumber: 1)])
        }
        await probe.waitUntilStarted()
        var edited = model.socksProxies[0]
        edited.password = "new password"
        try model.updateSocksProxy(edited)
        await probe.release()
        let results = try await task.value
        #expect(results.isEmpty)
        #expect(model.socksProxies[0].password == "new password")
        #expect(model.socksProxies[0].lastLatencyCheck == nil)
    }

    @Test
    func cancelledMeasurementDoesNotSaveResults() async throws {
        let proxy = SocksProxy(host: "proxy.example", port: 1080)
        let probe = GatedGroupLatencyProbe()
        let fixture = try GroupProxyFixture(proxies: [proxy], probe: probe)
        defer { fixture.cleanUp() }
        let model = fixture.model
        let task = Task {
            try await model.validateGroupProxyLatencies(for: [BrowserProfile(name: "环境", socksProxyNumber: 1)])
        }
        await probe.waitUntilStarted()
        task.cancel()
        await probe.release()
        do {
            _ = try await task.value
            Issue.record("Cancelled measurement was accepted")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(model.socksProxies[0].lastLatencyCheck == nil)
        #expect(try fixture.proxyRepository.load()[0].lastLatencyCheck == nil)
    }
}

private actor GroupLatencyProbe: SocksProxyProbe {
    let results: [UUID: SocksProxyProbeResult]
    private(set) var calls: [UUID] = []

    init(results: [UUID: SocksProxyProbeResult]) { self.results = results }

    func probe(_ proxy: SocksProxy, timeout: TimeInterval) async throws -> SocksProxyProbeResult {
        calls.append(proxy.id)
        return results[proxy.id] ?? .init(status: .unavailable)
    }
}

private actor GatedGroupLatencyProbe: SocksProxyProbe {
    private var continuation: CheckedContinuation<SocksProxyProbeResult, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func probe(_ proxy: SocksProxy, timeout: TimeInterval) async throws -> SocksProxyProbeResult {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started?.resume()
            started = nil
        }
    }

    func waitUntilStarted() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { started = $0 }
    }

    func release() {
        continuation?.resume(returning: .init(status: .available, latencyMilliseconds: 20))
        continuation = nil
    }
}

@MainActor
private struct GroupProxyFixture {
    let directory: URL
    let suite: String
    let defaults: UserDefaults
    let profileRepository: ProfileRepository
    let proxyRepository: SocksProxyRepository
    let model: AppModel

    init(proxies: [SocksProxy], probe: any SocksProxyProbe) throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        suite = "Cweb.GroupProxyTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        profileRepository = ProfileRepository(fileURL: directory.appending(path: "profiles.json"))
        proxyRepository = SocksProxyRepository(
            fileURL: directory.appending(path: "proxies.json"),
            credentialStore: SocksProxyCredentialStore(inMemory: true)
        )
        try profileRepository.save([])
        try proxyRepository.save(proxies)
        model = AppModel(
            profileRepository: profileRepository,
            socksProxyRepository: proxyRepository,
            socksProxyValidationService: SocksProxyValidationService(timeout: 1, probe: probe),
            userDefaults: defaults
        )
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}
