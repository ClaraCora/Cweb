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
}
