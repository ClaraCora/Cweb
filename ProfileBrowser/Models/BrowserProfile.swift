import Foundation

struct BrowserProfile: Identifiable, Codable, Hashable, Sendable {
    static let defaultHomePage = URL(string: "https://duckduckgo.com")!
    static let defaultUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"

    let id: UUID
    var name: String
    var groupName: String?
    /// Stable identifier of the group this profile belongs to.  This is
    /// optional to keep profiles written by older versions decodable; legacy
    /// records continue to use `groupName` until they are migrated.
    var groupID: UUID?
    /// Optional group code/emoji copied onto each member so metadata remains
    /// part of the existing profiles.json format.  AppModel keeps all members
    /// of one group synchronized when the group is edited.
    var groupCode: String?
    var groupEmoji: String?
    var groupSortOrder: Int?
    let websiteDataStoreID: UUID
    var userAgent: String
    let fingerprintSeed: UUID
    var homePage: URL
    var color: ProfileColor
    var cachedBalance: String?
    /// The currently selected SOCKS display number. This intentionally points
    /// to the volatile ranked position rather than a proxy record ID: feed
    /// refreshes can replace the endpoint behind the same number.
    var socksProxyNumber: Int?
    let createdAt: Date
    var updatedAt: Date
    var lastOpenedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        groupName: String? = nil,
        groupID: UUID? = nil,
        groupCode: String? = nil,
        groupEmoji: String? = nil,
        groupSortOrder: Int? = nil,
        websiteDataStoreID: UUID = UUID(),
        userAgent: String = BrowserProfile.defaultUserAgent,
        fingerprintSeed: UUID = UUID(),
        homePage: URL = BrowserProfile.defaultHomePage,
        color: ProfileColor = .indigo,
        cachedBalance: String? = nil,
        socksProxyNumber: Int? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastOpenedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.groupName = groupName
        self.groupID = groupID
        self.groupCode = groupCode
        self.groupEmoji = groupEmoji
        self.groupSortOrder = groupSortOrder
        self.websiteDataStoreID = websiteDataStoreID
        self.userAgent = userAgent
        self.fingerprintSeed = fingerprintSeed
        self.homePage = homePage
        self.color = color
        self.cachedBalance = cachedBalance
        self.socksProxyNumber = socksProxyNumber
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
            value: "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1 Via/6.8.0"
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

    static func userAgentPresetName(for userAgent: String?) -> String {
        guard let userAgent else { return "iPhone Safari" }
        if userAgent.contains("UCBrowser/") { return "UC" }
        if userAgent.contains(" Via/") { return "Via" }
        if userAgent.contains("EdgiOS/") { return "Edge" }
        if userAgent.contains("CriOS/") { return "Chrome" }
        if userAgent.contains("Alook/") { return "Alook" }
        if userAgent.contains("FxiOS/") { return "Firefox" }
        if userAgent.contains("OPiOS/") { return "Opera" }
        if userAgent.contains("iPad") { return "iPad Safari" }
        return "iPhone Safari"
    }

    static func randomUserAgent(for presetName: String?) -> String {
        guard let presetName else {
            let name = userAgentPresets.randomElement()?.name
            return randomUserAgent(for: name)
        }

        switch presetName {
        case "iPhone Safari":
            return randomSafari(device: "iPhone")
        case "iPad Safari":
            return randomSafari(device: "iPad")
        case "UC":
            let version = randomIOSVersion()
            let browserVersion = "\(Int.random(in: 15...19)).\(Int.random(in: 0...9)).\(Int.random(in: 0...9)).\(Int.random(in: 1...999))"
            return "\(iosPrefix(version)) Mobile/15E148 Safari/604.1 UCBrowser/\(browserVersion)"
        case "Via":
            let version = randomIOSVersion()
            let appVersion = "\(Int.random(in: 6...7)).\(Int.random(in: 0...9)).\(Int.random(in: 0...9))"
            return "\(iosPrefix(version)) Version/\(version.major).\(version.minor) Mobile/15E148 Safari/604.1 Via/\(appVersion)"
        case "Edge":
            let version = randomIOSVersion()
            let browserVersion = "\(Int.random(in: 128...141)).\(Int.random(in: 0...9)).\(Int.random(in: 3000...5999)).\(Int.random(in: 1...199))"
            return "\(iosPrefix(version)) EdgiOS/\(browserVersion) Mobile/15E148 Safari/605.1.15"
        case "Chrome":
            let version = randomIOSVersion()
            let browserVersion = "\(Int.random(in: 128...141)).\(Int.random(in: 0...9_999)).\(Int.random(in: 1_000...9_999)).\(Int.random(in: 1...999))"
            return "\(iosPrefix(version)) CriOS/\(browserVersion) Mobile/15E148 Safari/604.1"
        case "Alook":
            let version = randomIOSVersion()
            let appVersion = "1.\(Int.random(in: 0...9)).\(Int.random(in: 0...99))"
            return "\(iosPrefix(version)) Version/\(version.major).\(version.minor) Mobile/15E148 Safari/604.1 Alook/\(appVersion)"
        case "Firefox":
            let version = randomIOSVersion()
            let browserVersion = "\(Int.random(in: 128...143)).\(Int.random(in: 0...9)).\(Int.random(in: 0...9))"
            return "\(iosPrefix(version)) FxiOS/\(browserVersion) Mobile/15E148 Safari/605.1.15"
        case "Opera":
            let version = randomIOSVersion()
            let browserVersion = "\(Int.random(in: 2...3)).\(Int.random(in: 0...9)).\(Int.random(in: 0...9)).\(Int.random(in: 10_000...99_999))"
            return "\(iosPrefix(version)) Version/\(version.major).\(version.minor) Mobile/15E148 Safari/604.1 OPiOS/\(browserVersion)"
        default:
            return userAgentPresets.first(where: { $0.name == presetName })?.value ?? defaultUserAgent
        }
    }

    private static func randomSafari(device: String) -> String {
        let version = randomIOSVersion()
        return "\(iosPrefix(version, device: device)) Version/\(version.major).\(version.minor) Mobile/15E148 Safari/\(randomSafariBuild(for: version.major))"
    }

    private static func randomIOSVersion() -> (major: Int, minor: Int) {
        let major = [17, 18, 26].randomElement() ?? 18
        let minor = major == 26 ? Int.random(in: 0...2) : Int.random(in: 0...7)
        return (major, minor)
    }

    private static func iosPrefix(
        _ version: (major: Int, minor: Int),
        device: String = "iPhone"
    ) -> String {
        if device == "iPad" {
            return "Mozilla/5.0 (iPad; CPU OS \(version.major)_\(version.minor) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko)"
        }
        return "Mozilla/5.0 (iPhone; CPU iPhone OS \(version.major)_\(version.minor) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko)"
    }

    private static func randomSafariBuild(for major: Int) -> String {
        if major <= 17 {
            return Bool.random() ? "604.1" : "605.1.15"
        }
        return "605.1.15"
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
