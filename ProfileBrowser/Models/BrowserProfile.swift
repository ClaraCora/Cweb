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
    var cachedBalance: String?
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
        cachedBalance: String? = nil,
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
        self.cachedBalance = cachedBalance
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

    static let userAgentPresets: [UserAgentPreset] = [
        UserAgentPreset(name: "iPhone Safari", value: defaultUserAgent),
        UserAgentPreset(
            name: "iPad Safari",
            value: "Mozilla/5.0 (iPad; CPU OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"
        ),
        UserAgentPreset(
            name: "UC",
            value: "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Safari/604.1 UCBrowser/19.7.2.1"
        ),
        UserAgentPreset(
            name: "Via",
            value: "Mozilla/5.0 (Linux; Android 15; Pixel 8 Pro Build/AP3A.241105.007) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36 Via/6.8.0"
        ),
        UserAgentPreset(
            name: "Edge",
            value: "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) EdgiOS/140.0.3485.77 Mobile/15E148 Safari/605.1.15"
        ),
        UserAgentPreset(
            name: "Chrome",
            value: "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/140.0.7339.101 Mobile/15E148 Safari/604.1"
        ),
        UserAgentPreset(
            name: "Alook",
            value: "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1 Alook/1.0"
        ),
        UserAgentPreset(
            name: "Firefox",
            value: "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) FxiOS/142.0 Mobile/15E148 Safari/605.1.15"
        ),
        UserAgentPreset(
            name: "Opera",
            value: "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1 OPiOS/2.2.0.11266"
        )
    ]

    static func randomUserAgent() -> String {
        randomUserAgent(for: nil)
    }

    static func randomUserAgent(for presetName: String?) -> String {
        guard let presetName else {
            return userAgentPresets.randomElement()?.value ?? defaultUserAgent
        }

        let variants: [String: [String]] = [
            "iPhone Safari": [
                defaultUserAgent,
                "Mozilla/5.0 (iPhone; CPU iPhone OS 26_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.1 Mobile/15E148 Safari/604.1"
            ],
            "iPad Safari": [
                "Mozilla/5.0 (iPad; CPU OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1",
                "Mozilla/5.0 (iPad; CPU OS 26_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.1 Mobile/15E148 Safari/604.1"
            ],
            "UC": [
                "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Safari/604.1 UCBrowser/19.7.2.1",
                "Mozilla/5.0 (iPhone; CPU iPhone OS 26_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Safari/604.1 UCBrowser/19.8.0.1"
            ],
            "Via": [
                "Mozilla/5.0 (Linux; Android 15; Pixel 8 Pro Build/AP3A.241105.007) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36 Via/6.8.0",
                "Mozilla/5.0 (Linux; Android 15; Pixel 8 Pro Build/AP3A.241205.002) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Mobile Safari/537.36 Via/6.9.0"
            ],
            "Edge": [
                "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) EdgiOS/140.0.3485.77 Mobile/15E148 Safari/605.1.15",
                "Mozilla/5.0 (iPhone; CPU iPhone OS 26_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) EdgiOS/141.0.3537.32 Mobile/15E148 Safari/605.1.15"
            ],
            "Chrome": [
                "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/140.0.7339.101 Mobile/15E148 Safari/604.1",
                "Mozilla/5.0 (iPhone; CPU iPhone OS 26_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/141.0.7390.41 Mobile/15E148 Safari/604.1"
            ],
            "Alook": [
                "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1 Alook/1.0",
                "Mozilla/5.0 (iPhone; CPU iPhone OS 26_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.1 Mobile/15E148 Safari/604.1 Alook/1.1"
            ],
            "Firefox": [
                "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) FxiOS/142.0 Mobile/15E148 Safari/605.1.15",
                "Mozilla/5.0 (iPhone; CPU iPhone OS 26_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) FxiOS/143.0 Mobile/15E148 Safari/605.1.15"
            ],
            "Opera": [
                "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1 OPiOS/2.2.0.11266",
                "Mozilla/5.0 (iPhone; CPU iPhone OS 26_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.1 Mobile/15E148 Safari/604.1 OPiOS/2.2.0.11300"
            ]
        ]
        return variants[presetName]?.randomElement()
            ?? userAgentPresets.first(where: { $0.name == presetName })?.value
            ?? defaultUserAgent
    }
}

struct UserAgentPreset: Identifiable, Hashable, Sendable {
    let name: String
    let value: String

    var id: String { name }
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
