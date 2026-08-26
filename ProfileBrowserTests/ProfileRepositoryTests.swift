import Foundation
import Testing
@testable import ProfileBrowser

struct ProfileRepositoryTests {
    @Test
    func roundTripsProfiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let fileURL = directory.appending(path: "profiles.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = ProfileRepository(fileURL: fileURL)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let profile = BrowserProfile(
            name: "工作",
            homePage: try #require(URL(string: "https://example.com")),
            color: .teal,
            createdAt: timestamp,
            updatedAt: timestamp
        )

        try repository.save([profile])
        let loaded = try repository.load()

        #expect(loaded == [profile])
    }

    @Test
    func missingFileLoadsAsEmpty() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "profiles.json")
        let repository = ProfileRepository(fileURL: fileURL)

        #expect(try repository.load().isEmpty)
    }
}
