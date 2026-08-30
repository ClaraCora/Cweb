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
            cachedBalance: "$4.03",
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

    @Test
    func profilesWithoutGroupRemainCompatible() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let fileURL = directory.appending(path: "profiles.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let legacyJSON = """
        [{
          "color": "indigo",
          "createdAt": "2023-11-14T22:13:20Z",
          "fingerprintSeed": "00000000-0000-0000-0000-000000000001",
          "homePage": "https://example.com",
          "id": "00000000-0000-0000-0000-000000000002",
          "name": "旧环境",
          "updatedAt": "2023-11-14T22:13:20Z",
          "userAgent": "Mozilla/5.0",
          "websiteDataStoreID": "00000000-0000-0000-0000-000000000003"
        }]
        """.data(using: .utf8)!
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try legacyJSON.write(to: fileURL)

        let loaded = try ProfileRepository(fileURL: fileURL).load()

        #expect(loaded.count == 1)
        #expect(loaded[0].groupName == nil)
        #expect(loaded[0].cachedBalance == nil)
        #expect(loaded[0].displayGroupName == "未分组")
    }

    @Test
    func volatileSocksProxyNumberRoundTrips() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let fileURL = directory.appending(path: "profiles.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let profile = BrowserProfile(name: "代理环境", socksProxyNumber: 3)
        let repository = ProfileRepository(fileURL: fileURL)
        try repository.save([profile])

        let loaded = try repository.load()

        #expect(loaded.first?.socksProxyNumber == 3)
    }
}
