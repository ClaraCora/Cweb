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
    var balanceUpdatedAt: Date?
    var balanceReadError: String?
    var balanceSourceVerified: Bool?
    /// The currently selected SOCKS display number. This intentionally points
    /// to the volatile ranked position rather than a proxy record ID: feed
    /// refreshes can replace the endpoint behind the same number.
    var socksProxyNumber: Int?
    /// A copied or conflicting binding requires an explicit choice before any
    /// network request. It must never be confused with intentional direct use.
    var unresolvedProxyNumber: Int?
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
        unresolvedProxyNumber: Int? = nil,
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
        self.unresolvedProxyNumber = unresolvedProxyNumber
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
            value: "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Safari/604.1 UCBrowser/12.2.1.1264"
        ),
        UserAgentPreset(
            name: "Via",
            value: "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1 Via/1.9.0"
        ),
        UserAgentPreset(
            name: "Edge",
            value: "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) EdgiOS/152.0.4191.53 Mobile/15E148 Safari/605.1.15"
        ),
        UserAgentPreset(
            name: "Chrome",
            value: "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/152.0.7977.64 Mobile/15E148 Safari/604.1"
        ),
        UserAgentPreset(
            name: "Alook",
            value: "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1 Alook/23.0"
        ),
        UserAgentPreset(
            name: "Firefox",
            value: "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) FxiOS/155.0 Mobile/15E148 Safari/605.1.15"
        ),
        UserAgentPreset(
            name: "Opera",
            value: "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1 OPiOS/6.7.1"
        )
    ]

    static func randomUserAgent() -> String {
        randomUserAgent(for: nil)
    }

    static func userAgentPresetName(for userAgent: String?) -> String {
        UserAgentCatalog.browserName(for: userAgent)
    }

    static func randomUserAgent(for presetName: String?) -> String {
        uniqueRandomUserAgent(for: presetName, excluding: [])
            ?? userAgentPresets.first(where: { $0.name == presetName })?.value
            ?? defaultUserAgent
    }

    static func uniqueRandomUserAgent(
        for presetName: String?,
        excluding excludedValues: Set<String>,
        maximumOSVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) -> String? {
        let browserNames = presetName.map { [$0] }
            ?? userAgentPresets.map(\.name).shuffled()

        for browserName in browserNames {
            let candidates = UserAgentCatalog.candidates(
                for: browserName,
                maximumOSVersion: maximumOSVersion
            )
                .filter { !excludedValues.contains($0) }
            if let candidate = candidates.randomElement() {
                return candidate
            }
        }
        return nil
    }

    static func userAgentCandidates(
        for presetName: String,
        maximumOSVersion: OperatingSystemVersion
    ) -> [String] {
        UserAgentCatalog.candidates(
            for: presetName,
            maximumOSVersion: maximumOSVersion
        )
    }

    static func userAgentDetails(for userAgent: String) -> UserAgentDetails? {
        UserAgentCatalog.details(for: userAgent)
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
