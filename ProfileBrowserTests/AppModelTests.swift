import Foundation
import Testing
@testable import ProfileBrowser

@MainActor
struct AppModelTests {
    @Test
    func transientProfileReadFailureRecoversWithoutShowingAnEmptyStore() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let fileURL = directory.appending(path: "profiles.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let expected = BrowserProfile(name: "保留的环境", groupName: "工作")
        let writer = ProfileRepository(fileURL: fileURL)
        try writer.save([expected])

        var readAttempt = 0
        let repository = ProfileRepository(fileURL: fileURL) { url in
            readAttempt += 1
            if readAttempt == 1 {
                throw CocoaError(.fileReadUnknown)
            }
            return try Data(contentsOf: url)
        }
        let model = AppModel(profileRepository: repository)

        #expect(model.isLoadingProfiles)
        #expect(!model.isProfileStoreAvailable)
        #expect(model.profiles.isEmpty)

        await model.retryLoadingProfiles()

        #expect(!model.isLoadingProfiles)
        #expect(model.isProfileStoreAvailable)
        #expect(model.profiles.map(\.id) == [expected.id])
        #expect(model.profileGroups.map(\.name) == ["工作"])
    }

    @Test
    func unavailableProfileStoreCannotBeOverwrittenAsEmpty() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let fileURL = directory.appending(path: "profiles.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let originalData = Data("not available yet".utf8)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try originalData.write(to: fileURL)
        let repository = ProfileRepository(fileURL: fileURL) { _ in
            throw CocoaError(.fileReadNoPermission)
        }
        let model = AppModel(profileRepository: repository)

        #expect(throws: ProfileError.profileStoreUnavailable) {
            try model.addProfile(
                name: "不能覆盖",
                homePage: BrowserProfile.defaultHomePage,
                userAgent: BrowserProfile.defaultUserAgent,
                color: .indigo
            )
        }
        #expect(model.profiles.isEmpty)
        #expect(try Data(contentsOf: fileURL) == originalData)
    }

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

        let migratedGroupIDs = model.profileGroups.map(\.id)
        let reloaded = AppModel(profileRepository: repository)
        #expect(reloaded.profileGroups.map(\.id) == migratedGroupIDs)
        #expect(reloaded.profileGroups.map(\.sortOrder) == [0, 1, 2])
    }

    @Test
    func movingGroupsPersistsWithoutChangingEnvironmentOrder() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let fileURL = directory.appending(path: "profiles.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let profiles = [
            BrowserProfile(name: "甲一", groupName: "甲"),
            BrowserProfile(name: "乙一", groupName: "乙"),
            BrowserProfile(name: "甲二", groupName: "甲"),
            BrowserProfile(name: "丙一", groupName: "丙"),
            BrowserProfile(name: "乙二", groupName: "乙")
        ]
        let repository = ProfileRepository(fileURL: fileURL)
        try repository.save(profiles)
        let model = AppModel(profileRepository: repository)
        let originalProfileIDs = model.profiles.map(\.id)

        try model.moveGroups(
            fromOffsets: IndexSet(integer: 0),
            toOffset: 3
        )

        #expect(model.profileGroups.map(\.name) == ["乙", "丙", "甲"])
        #expect(model.profiles.map(\.id) == originalProfileIDs)

        let reloaded = AppModel(profileRepository: repository)
        #expect(reloaded.profileGroups.map(\.name) == ["乙", "丙", "甲"])
        #expect(reloaded.profiles.map(\.id) == originalProfileIDs)
        #expect(reloaded.profileGroups.map(\.sortOrder) == [0, 1, 2])
    }

    @Test
    func importingProfilesAppendsNewGroupsInTheirSavedOrder() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let fileURL = directory.appending(path: "profiles.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let existing = BrowserProfile(name: "已有", groupName: "已有组")
        let imported = [
            BrowserProfile(name: "甲一", groupName: "甲", groupSortOrder: 2),
            BrowserProfile(name: "乙一", groupName: "乙", groupSortOrder: 0),
            BrowserProfile(name: "甲二", groupName: "甲", groupSortOrder: 2)
        ]
        let repository = ProfileRepository(fileURL: fileURL)
        try repository.save([existing])
        let model = AppModel(profileRepository: repository)

        try model.addImportedProfiles(imported)

        #expect(model.profileGroups.map(\.name) == ["已有组", "乙", "甲"])
        #expect(model.profiles.map(\.id) == [existing.id] + imported.map(\.id))
        #expect(model.profileGroups.last?.profiles.map(\.name) == ["甲一", "甲二"])

        let reloaded = AppModel(profileRepository: repository)
        #expect(reloaded.profileGroups.map(\.name) == ["已有组", "乙", "甲"])
        #expect(reloaded.profiles.map(\.id) == [existing.id] + imported.map(\.id))
    }

    @Test
    func updatingGroupPersistsMetadataAndRenamesDerivedProfileNames() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let fileURL = directory.appending(path: "profiles.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let derived = BrowserProfile(name: "旧站点 1", groupName: "旧站点")
        let custom = BrowserProfile(name: "主账号", groupName: "旧站点")
        let repository = ProfileRepository(fileURL: fileURL)
        try repository.save([derived, custom])

        let model = AppModel(profileRepository: repository)
        let group = try #require(model.profileGroups.first)
        try model.updateGroup(id: group.id, name: "新站点", code: "NEW", emoji: "🧪")

        #expect(model.profileGroups.map(\.name) == ["新站点"])
        #expect(model.profileGroups[0].displayCode == "NEW")
        #expect(model.profileGroups[0].displayEmoji == "🧪")
        #expect(model.profiles[0].name == "新站点 1")
        #expect(model.profiles[1].name == "主账号")
        #expect(model.profiles.allSatisfy { $0.groupName == "新站点" })

        let reloaded = AppModel(profileRepository: repository)
        #expect(reloaded.profileGroups.first?.id == group.id)
        #expect(reloaded.profileGroups.first?.displayEmoji == "🧪")
        #expect(reloaded.profiles[0].name == "新站点 1")
    }

    @Test
    func duplicateGroupNamesAreRejectedWithoutChangingProfiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let fileURL = directory.appending(path: "profiles.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = BrowserProfile(name: "一", groupName: "甲")
        let second = BrowserProfile(name: "二", groupName: "乙")
        let repository = ProfileRepository(fileURL: fileURL)
        try repository.save([first, second])
        let model = AppModel(profileRepository: repository)
        let source = try #require(model.profileGroups.first)

        #expect(throws: ProfileError.groupNameAlreadyExists) {
            try model.updateGroup(id: source.id, name: "乙", code: nil, emoji: nil)
        }
        #expect(model.profiles.map(\.groupName) == ["甲", "乙"])
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

    @Test
    func socksProxyNumbersAreUniqueWithinOneGroupButReusableAcrossGroups() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let profileURL = directory.appending(path: "profiles.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = ProfileRepository(fileURL: profileURL)
        let model = AppModel(profileRepository: repository)
        try model.addProfile(
            name: "甲一",
            groupName: "甲",
            homePage: BrowserProfile.defaultHomePage,
            userAgent: BrowserProfile.defaultUserAgent,
            color: .indigo,
            socksProxyNumber: 1
        )
        try model.addProfile(
            name: "乙一",
            groupName: "乙",
            homePage: BrowserProfile.defaultHomePage,
            userAgent: BrowserProfile.defaultUserAgent,
            color: .indigo,
            socksProxyNumber: 1
        )

        #expect(throws: ProfileError.self) {
            try model.addProfile(
                name: "甲二",
                groupName: "甲",
                homePage: BrowserProfile.defaultHomePage,
                userAgent: BrowserProfile.defaultUserAgent,
                color: .indigo,
                socksProxyNumber: 1
            )
        }
        #expect(model.profiles.map(\.name) == ["甲一", "乙一"])
    }

    @Test
    func movingToGroupWithAssignedProxyIsRejected() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let profileURL = directory.appending(path: "profiles.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = ProfileRepository(fileURL: profileURL)
        let model = AppModel(profileRepository: repository)
        try model.addProfile(
            name: "甲一", groupName: "甲", homePage: BrowserProfile.defaultHomePage,
            userAgent: BrowserProfile.defaultUserAgent, color: .indigo, socksProxyNumber: 1
        )
        try model.addProfile(
            name: "乙一", groupName: "乙", homePage: BrowserProfile.defaultHomePage,
            userAgent: BrowserProfile.defaultUserAgent, color: .indigo, socksProxyNumber: 1
        )

        let originalSecond = try #require(model.profiles.last)
        // Saving the existing assignment for the same environment is valid.
        try model.updateProfile(originalSecond)

        var movedSecond = originalSecond
        movedSecond.groupName = "甲"
        #expect(throws: ProfileError.self) {
            try model.updateProfile(movedSecond)
        }
        let persistedSecond = try #require(model.profiles.last)
        #expect(persistedSecond.groupName == "乙")
    }

    @Test
    func duplicatingProfileClearsSocksProxySelection() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let profileURL = directory.appending(path: "profiles.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = ProfileRepository(fileURL: profileURL)
        let model = AppModel(profileRepository: repository)
        try model.addProfile(
            name: "环境", groupName: "甲", homePage: BrowserProfile.defaultHomePage,
            userAgent: BrowserProfile.defaultUserAgent, color: .indigo, socksProxyNumber: 1
        )

        try model.duplicateProfile(try #require(model.profiles.first))
        #expect(model.profiles.map(\.socksProxyNumber) == [1, nil])
    }

    @Test
    func importedConflictingSocksProxySelectionIsCleared() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let profileURL = directory.appending(path: "profiles.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = ProfileRepository(fileURL: profileURL)
        let model = AppModel(profileRepository: repository)
        try model.addProfile(
            name: "已有", groupName: "甲", homePage: BrowserProfile.defaultHomePage,
            userAgent: BrowserProfile.defaultUserAgent, color: .indigo, socksProxyNumber: 1
        )

        try model.addImportedProfiles([
            BrowserProfile(name: "冲突", groupName: "甲", socksProxyNumber: 1),
            BrowserProfile(name: "可用", groupName: "乙", socksProxyNumber: 1)
        ])

        #expect(model.profiles.map(\.socksProxyNumber) == [1, nil, 1])
    }

    @Test
    func existingDuplicateSocksProxySelectionsAreRepairedInPersistedOrder() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let profileURL = directory.appending(path: "profiles.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = BrowserProfile(name: "先保存", groupName: "甲", socksProxyNumber: 1)
        let second = BrowserProfile(name: "后保存", groupName: "甲", socksProxyNumber: 1)
        let third = BrowserProfile(name: "另一组", groupName: "乙", socksProxyNumber: 1)
        let repository = ProfileRepository(fileURL: profileURL)
        try repository.save([first, second, third])

        let model = AppModel(profileRepository: repository)
        #expect(model.profiles.map(\.socksProxyNumber) == [1, nil, 1])
        #expect(try repository.load().map(\.socksProxyNumber) == [1, nil, 1])
    }

    @Test
    func lockedProxiesSurviveSingleBatchAndClearDeletion() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let profileURL = directory.appending(path: "profiles.json")
        let proxyURL = directory.appending(path: "proxies.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let locked = SocksProxy(isLocked: true, host: "locked.example", port: 1080)
        let batchDelete = SocksProxy(host: "batch.example", port: 1080)
        let clearDelete = SocksProxy(host: "clear.example", port: 1080)
        let profileRepository = ProfileRepository(fileURL: profileURL)
        let proxyRepository = SocksProxyRepository(
            fileURL: proxyURL,
            credentialStore: SocksProxyCredentialStore(inMemory: true)
        )
        try proxyRepository.save([locked, batchDelete, clearDelete])
        let model = AppModel(
            profileRepository: profileRepository,
            socksProxyRepository: proxyRepository
        )

        try model.setSocksProxyLocked(false, for: locked)
        let unlockedReloaded = try proxyRepository.load()
        #expect(!unlockedReloaded[0].isLocked)
        try model.setSocksProxyLocked(true, for: locked)
        let lockedReloaded = try proxyRepository.load()
        #expect(lockedReloaded[0].isLocked)

        #expect(throws: SocksProxyError.proxyLocked) {
            try model.deleteSocksProxy(locked)
        }
        let batchCount = try model.deleteSocksProxies(
            withIDs: Set([locked.id, batchDelete.id])
        )
        #expect(batchCount == 1)
        #expect(model.socksProxies.map(\.id) == [locked.id, clearDelete.id])

        let clearCount = try model.clearSocksProxies()
        #expect(clearCount == 1)
        #expect(model.socksProxies.map(\.id) == [locked.id])
        #expect(try proxyRepository.load().map(\.id) == [locked.id])
    }

    @Test
    func lockedProxySurvivesValidationRetentionRules() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let profileURL = directory.appending(path: "profiles.json")
        let proxyURL = directory.appending(path: "proxies.json")
        let settingsURL = directory.appending(path: "settings.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let locked = SocksProxy(isLocked: true, host: "locked.example", port: 1080)
        let fast = SocksProxy(host: "fast.example", port: 1080)
        let slow = SocksProxy(host: "slow.example", port: 1080)
        let profileRepository = ProfileRepository(fileURL: profileURL)
        let proxyRepository = SocksProxyRepository(
            fileURL: proxyURL,
            settingsFileURL: settingsURL,
            credentialStore: SocksProxyCredentialStore(inMemory: true)
        )
        try proxyRepository.save([locked, fast, slow])

        let probe = AppModelStubProbe(results: [
            locked.id: SocksProxyProbeResult(status: .unavailable, message: "offline"),
            fast.id: SocksProxyProbeResult(status: .available, latencyMilliseconds: 20),
            slow.id: SocksProxyProbeResult(status: .available, latencyMilliseconds: 80)
        ])
        let model = AppModel(
            profileRepository: profileRepository,
            socksProxyRepository: proxyRepository,
            socksProxyValidationService: SocksProxyValidationService(timeout: 1, probe: probe)
        )
        try model.updateSocksProxyValidationSettings(
            SocksProxyValidationSettings(
                retainOnlyAvailable: true,
                maxRetainedCount: 2,
                sortMode: .latencyAscending
            )
        )

        try await model.validateSocksProxies()

        #expect(model.socksProxies.map(\.id) == [locked.id, fast.id])
        #expect(model.socksProxies.first?.status == .unavailable)
        #expect(try proxyRepository.load().map(\.id) == [locked.id, fast.id])
    }

    @Test
    func batchValidationHonorsRetentionAndKeepsPersistedInputOrder() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let profileURL = directory.appending(path: "profiles.json")
        let proxyURL = directory.appending(path: "proxies.json")
        let settingsURL = directory.appending(path: "settings.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = SocksProxy(host: "slow.example", port: 1080)
        let second = SocksProxy(host: "fast.example", port: 1080)
        let third = SocksProxy(host: "offline.example", port: 1080)
        let profileRepository = ProfileRepository(fileURL: profileURL)
        let proxyRepository = SocksProxyRepository(
            fileURL: proxyURL,
            settingsFileURL: settingsURL,
            credentialStore: SocksProxyCredentialStore(inMemory: true)
        )
        try proxyRepository.save([first, second, third])

        let probe = AppModelStubProbe(results: [
            first.id: SocksProxyProbeResult(status: .available, latencyMilliseconds: 80),
            second.id: SocksProxyProbeResult(status: .available, latencyMilliseconds: 20),
            third.id: SocksProxyProbeResult(status: .unavailable, message: "offline")
        ])
        let model = AppModel(
            profileRepository: profileRepository,
            socksProxyRepository: proxyRepository,
            socksProxyValidationService: SocksProxyValidationService(timeout: 1, probe: probe)
        )
        try model.updateSocksProxyValidationSettings(
            SocksProxyValidationSettings(
                retainOnlyAvailable: true,
                maxRetainedCount: 2,
                sortMode: .latencyAscending
            )
        )

        try await model.validateSocksProxies()

        #expect(model.socksProxies.map(\.id) == [first.id, second.id])
        #expect(try proxyRepository.load().map(\.id) == [first.id, second.id])
        #expect(model.rankedSocksProxies.map(\.proxy.id) == [second.id, first.id])
        #expect(model.socksProxy(forDisplayNumber: 1)?.id == second.id)
    }

    @Test
    func inputOrderSettingKeepsDisplayNumbersAndTargetChangesInvalidateResults() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let profileURL = directory.appending(path: "profiles.json")
        let proxyURL = directory.appending(path: "proxies.json")
        let settingsURL = directory.appending(path: "settings.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = SocksProxy(
            host: "first.example",
            port: 1080,
            latencyMilliseconds: 20,
            status: .available
        )
        let second = SocksProxy(
            host: "second.example",
            port: 1080,
            latencyMilliseconds: 10,
            status: .available
        )
        let profileRepository = ProfileRepository(fileURL: profileURL)
        let proxyRepository = SocksProxyRepository(
            fileURL: proxyURL,
            settingsFileURL: settingsURL,
            credentialStore: SocksProxyCredentialStore(inMemory: true)
        )
        try proxyRepository.save([first, second])
        let model = AppModel(
            profileRepository: profileRepository,
            socksProxyRepository: proxyRepository
        )

        try model.updateSocksProxyValidationSettings(
            SocksProxyValidationSettings(sortMode: .inputOrder)
        )
        #expect(model.rankedSocksProxies.map(\.proxy.id) == [first.id, second.id])
        #expect(model.socksProxy(forDisplayNumber: 1)?.id == first.id)

        try model.updateSocksProxyValidationSettings(
            SocksProxyValidationSettings(targetURLString: "https://example.com/generate_204")
        )
        #expect(model.socksProxies.allSatisfy { $0.status == .untested })
        #expect(model.socksProxies.allSatisfy { $0.latencyMilliseconds == nil })
    }
}

private struct AppModelStubProbe: SocksProxyProbe {
    let results: [UUID: SocksProxyProbeResult]

    func probe(_ proxy: SocksProxy, timeout: TimeInterval) async throws -> SocksProxyProbeResult {
        results[proxy.id] ?? SocksProxyProbeResult(status: .unavailable, message: "missing result")
    }
}
