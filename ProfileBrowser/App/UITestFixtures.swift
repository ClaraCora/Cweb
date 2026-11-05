import Foundation

extension AppModel {
    static func launchModel() -> AppModel {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            do { return try makeUITestModel() }
            catch { fatalError("Cannot prepare isolated UI fixtures: \(error)") }
        }
#endif
        return AppModel()
    }

#if DEBUG
    private static func makeUITestModel() throws -> AppModel {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ui-fixtures", directoryHint: .isDirectory)
        let repository = ProfileRepository(fileURL: directory.appending(path: "profiles.json"))
        let proxyRepository = SocksProxyRepository(fileURL: directory.appending(path: "proxies.json"), credentialStore: SocksProxyCredentialStore(inMemory: true))
        let groupID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let profiles = [
            BrowserProfile(id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!, name: "主账号", groupName: "示例分组", groupID: groupID,
                homePage: URL(string: "https://example.test")!, cachedBalance: "$12.50", socksProxyNumber: 1),
            BrowserProfile(id: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!, name: "用于验证长名称与无障碍字号的环境", groupName: "示例分组", groupID: groupID,
                homePage: URL(string: "https://example.test")!, cachedBalance: "$1,234.56"),
            BrowserProfile(id: UUID(uuidString: "20000000-0000-0000-0000-000000000003")!, name: "备用账号", groupName: "示例分组", groupID: groupID,
                homePage: URL(string: "https://example.test")!, socksProxyNumber: 2),
            BrowserProfile(id: UUID(uuidString: "20000000-0000-0000-0000-000000000004")!, name: "独立账号", groupName: "示例分组", groupID: groupID,
                homePage: URL(string: "https://example.test")!, socksProxyNumber: 3),
            BrowserProfile(id: UUID(uuidString: "20000000-0000-0000-0000-000000000005")!, name: "等待选择代理", groupName: "示例分组", groupID: groupID,
                homePage: URL(string: "https://example.test")!, socksProxyNumber: 6),
            BrowserProfile(id: UUID(uuidString: "20000000-0000-0000-0000-000000000006")!, name: "其他环境", groupName: "用于验证较长名称和代号的分组", groupID: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
                homePage: URL(string: "https://example.test")!)
        ]
        try repository.save(profiles)
        let proxies = [SocksProxy(code: "东京", host: "127.0.0.1", port: 1080, latencyMilliseconds: 480, status: .available, lastCheckedAt: .now),
                       SocksProxy(code: "香港", host: "127.0.0.2", port: 1080, latencyMilliseconds: 1250, status: .available, lastCheckedAt: .now),
                       SocksProxy(code: "新加坡", host: "127.0.0.3", port: 1080, latencyMilliseconds: 2500, status: .available, lastCheckedAt: .now),
                       SocksProxy(code: "连接失败", host: "127.0.0.4", port: 1080, status: .unavailable, lastCheckedAt: .now),
                       SocksProxy(code: "锁定代理的较长代号与未测速状态", isLocked: true, host: "127.0.0.5", port: 1080)]
        try proxyRepository.save(proxies)
        let suite = "Cweb.UITestFixtures"
        let defaults = UserDefaults(suiteName: suite)!
        if !ProcessInfo.processInfo.arguments.contains("-ui-test-resume") { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(profileRepository: repository, credentialVault: CredentialVault(inMemory: true), socksProxyRepository: proxyRepository, userDefaults: defaults)
        for profile in model.profiles { model.confirmEntry(for: profile) }
        if ProcessInfo.processInfo.arguments.contains("-ui-test-completed") {
            for profile in model.profiles.prefix(2) { model.recordAutomationSuccess(for: profile.id) }
        }
        return model
    }
#endif
}
