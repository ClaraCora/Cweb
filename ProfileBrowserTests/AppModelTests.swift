import Foundation
import Testing
@testable import ProfileBrowser

@MainActor
struct AppModelTests {
    @Test
    func openingProfileDoesNotChangePersistedOrder() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let fileURL = directory.appending(path: "profiles.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let profiles = [
            BrowserProfile(name: "第一个"),
            BrowserProfile(name: "第二个"),
            BrowserProfile(name: "第三个")
        ]
        let repository = ProfileRepository(fileURL: fileURL)
        try repository.save(profiles)
        let model = AppModel(profileRepository: repository)

        model.markOpened(model.profiles[1])

        #expect(model.sortedProfiles.map(\.id) == profiles.map(\.id))
        #expect(try repository.load().map(\.id) == profiles.map(\.id))
    }

    @Test
    func movingProfilesPersistsTheNewOrder() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let fileURL = directory.appending(path: "profiles.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let profiles = [
            BrowserProfile(name: "第一个"),
            BrowserProfile(name: "第二个"),
            BrowserProfile(name: "第三个")
        ]
        let repository = ProfileRepository(fileURL: fileURL)
        try repository.save(profiles)
        let model = AppModel(profileRepository: repository)

        try model.moveProfiles(
            profiles.map(\.id),
            fromOffsets: IndexSet(integer: 0),
            toOffset: 3
        )

        let expected = [profiles[1], profiles[2], profiles[0]].map(\.id)
        #expect(model.profiles.map(\.id) == expected)
        #expect(try repository.load().map(\.id) == expected)
    }

    @Test
    func profileGroupsFollowPersistedProfileOrderAndIncludeUnassigned() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let fileURL = directory.appending(path: "profiles.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let profiles = [
            BrowserProfile(name: "工作一", groupName: "工作"),
            BrowserProfile(name: "个人", groupName: nil),
            BrowserProfile(name: "工作二", groupName: "工作"),
            BrowserProfile(name: "测试", groupName: "测试")
        ]
        let repository = ProfileRepository(fileURL: fileURL)
        try repository.save(profiles)
        let model = AppModel(profileRepository: repository)

        #expect(model.profileGroups.map(\.name) == ["工作", "未分组", "测试"])
        #expect(model.profileGroups[0].profiles.map(\.id) == [profiles[0].id, profiles[2].id])
        #expect(model.profileGroups[1].profiles.map(\.id) == [profiles[1].id])
    }

    @Test
    func deletingProfileRemovesPersistedProfileAndCredentials() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let fileURL = directory.appending(path: "profiles.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let profile = BrowserProfile(name: "待删除")
        let repository = ProfileRepository(fileURL: fileURL)
        let vault = CredentialVault(inMemory: true)
        try repository.save([profile])
        let origin = try #require(WebOrigin(url: URL(string: "https://example.com")!))
        try vault.save(
            StoredCredential(
                profileID: profile.id,
                origin: origin,
                username: "name",
                password: "password",
                label: "自动填充"
            )
        )
        let model = AppModel(profileRepository: repository, credentialVault: vault)

        await model.deleteProfile(profile)

        #expect(model.profiles.isEmpty)
        #expect(try repository.load().isEmpty)
        #expect(try vault.credentials(profileID: profile.id).isEmpty)
    }

    @Test
    func deletingGroupRemovesOnlyProfilesAndCredentialsInThatGroup() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let fileURL = directory.appending(path: "profiles.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = BrowserProfile(name: "工作一", groupName: "工作")
        let second = BrowserProfile(name: "工作二", groupName: "工作")
        let retained = BrowserProfile(name: "个人", groupName: "个人")
        let repository = ProfileRepository(fileURL: fileURL)
        let vault = CredentialVault(inMemory: true)
        try repository.save([first, second, retained])
        let origin = try #require(WebOrigin(url: URL(string: "https://example.com")!))
        for profile in [first, second, retained] {
            try vault.save(
                StoredCredential(
                    profileID: profile.id,
                    origin: origin,
                    username: profile.name,
                    password: "password"
                )
            )
        }
        let model = AppModel(profileRepository: repository, credentialVault: vault)

        await model.deleteProfiles(inGroupNamed: "工作")

        #expect(model.profiles.map(\.id) == [retained.id])
        #expect(try repository.load().map(\.id) == [retained.id])
        #expect(try vault.credentials(profileID: first.id).isEmpty)
        #expect(try vault.credentials(profileID: second.id).isEmpty)
        #expect(try vault.credentials(profileID: retained.id).count == 1)
    }

    @Test
    func profileProxySelectionFollowsCurrentDisplayNumber() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let profileURL = directory.appending(path: "profiles.json")
        let proxyURL = directory.appending(path: "proxies.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let profile = BrowserProfile(name: "时效代理", socksProxyNumber: 1)
        let slow = SocksProxy(
            host: "slow.example",
            port: 1080,
            latencyMilliseconds: 80,
            status: .available
        )
        let fast = SocksProxy(
            host: "fast.example",
            port: 1080,
            latencyMilliseconds: 20,
            status: .available
        )
        let profileRepository = ProfileRepository(fileURL: profileURL)
        let proxyRepository = SocksProxyRepository(
            fileURL: proxyURL,
            credentialStore: SocksProxyCredentialStore(inMemory: true)
        )
        try profileRepository.save([profile])
        try proxyRepository.save([slow, fast])

        let firstModel = AppModel(
            profileRepository: profileRepository,
            socksProxyRepository: proxyRepository
        )
        #expect(firstModel.socksProxy(for: profile)?.id == fast.id)

        let refreshedSlow = SocksProxy(
            id: slow.id,
            host: slow.host,
            port: slow.port,
            latencyMilliseconds: 10,
            status: .available
        )
        try proxyRepository.save([refreshedSlow, fast])

        let refreshedModel = AppModel(
            profileRepository: profileRepository,
            socksProxyRepository: proxyRepository
        )
        #expect(refreshedModel.socksProxy(for: profile)?.id == refreshedSlow.id)
    }
}
