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
            BrowserProfile(name: "用于验证长名称与无障碍字号的环境", groupName: "示例分组", groupID: groupID, homePage: URL(string: "https://example.test")!)
        ]
        try repository.save(profiles)
        let proxies = [SocksProxy(code: "东京", host: "127.0.0.1", port: 1080, latencyMilliseconds: 480, status: .available, lastCheckedAt: .now),
                       SocksProxy(code: "香港", host: "127.0.0.2", port: 1080, latencyMilliseconds: 1250, status: .available, lastCheckedAt: .now),
                       SocksProxy(code: "新加坡", host: "127.0.0.3", port: 1080, latencyMilliseconds: 2500, status: .available, lastCheckedAt: .now)]
        try proxyRepository.save(proxies)
        let suite = "Cweb.UITestFixtures"
        let defaults = UserDefaults(suiteName: suite)!
        if !ProcessInfo.processInfo.arguments.contains("-ui-test-resume") { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(profileRepository: repository, credentialVault: CredentialVault(inMemory: true), socksProxyRepository: proxyRepository, userDefaults: defaults)
        for profile in model.profiles { model.confirmEntry(for: profile) }
        return model
    }
#endif
}
