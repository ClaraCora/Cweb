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
}
