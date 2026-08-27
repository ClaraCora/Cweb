import Foundation

struct BrowserProfile: Identifiable, Codable, Hashable, Sendable {
    static let defaultHomePage = URL(string: "https://duckduckgo.com")!
    static let defaultUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"

    let id: UUID
    var name: String
    var groupName: String?
    let websiteDataStoreID: UUID
    var userAgent: String
    let fingerprintSeed: UUID
    var homePage: URL
    var color: ProfileColor
    let createdAt: Date
    var updatedAt: Date
    var lastOpenedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        groupName: String? = nil,
        websiteDataStoreID: UUID = UUID(),
        userAgent: String = BrowserProfile.defaultUserAgent,
        fingerprintSeed: UUID = UUID(),
        homePage: URL = BrowserProfile.defaultHomePage,
        color: ProfileColor = .indigo,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastOpenedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.groupName = groupName
        self.websiteDataStoreID = websiteDataStoreID
        self.userAgent = userAgent
        self.fingerprintSeed = fingerprintSeed
        self.homePage = homePage
        self.color = color
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastOpenedAt = lastOpenedAt
    }

    var homePageHost: String {
        homePage.host(percentEncoded: false) ?? homePage.absoluteString
    }

    var displayGroupName: String {
        let trimmed = groupName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "未分组" : trimmed
    }

    static func randomUserAgent() -> String {
        let candidates = [
            "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1",
            "Mozilla/5.0 (iPhone; CPU iPhone OS 26_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.1 Mobile/15E148 Safari/604.1",
            "Mozilla/5.0 (iPad; CPU OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1",
            "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/140.0.7339.101 Mobile/15E148 Safari/604.1",
            "Mozilla/5.0 (iPad; CPU OS 26_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/140.0.7339.101 Mobile/15E148 Safari/604.1"
        ]
        return candidates.randomElement() ?? defaultUserAgent
    }
}

enum ProfileColor: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case indigo
    case teal
    case green
    case orange
    case pink
    case red

    var id: Self { self }
}
