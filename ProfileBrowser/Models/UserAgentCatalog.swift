import Foundation

struct UserAgentDetails: Equatable, Sendable {
    let browserName: String
    let deviceName: String
    let operatingSystemVersion: String
    let browserVersion: String?

    var summary: String {
        var parts = [browserName, deviceName, "iOS \(operatingSystemVersion)"]
        if let browserVersion {
            parts.append(browserVersion)
        }
        return parts.joined(separator: " · ")
    }
}

enum UserAgentCatalog {
    private struct IOSRelease: Hashable, Sendable {
        let major: Int
        let minor: Int
        let patch: Int

        var numericValue: Int {
            major * 1_000_000 + minor * 1_000 + patch
        }

        var userAgentVersion: String {
            patch == 0
                ? "\(major)_\(minor)"
                : "\(major)_\(minor)_\(patch)"
        }

        var safariVersion: String {
            "\(major).\(minor)"
        }
    }

    // Publicly released iOS 17 and iOS 18 versions. The exact current device
    // version is added separately, so a future OS is never fabricated.
    private static let auditedIOSReleases: [IOSRelease] = [
        IOSRelease(major: 17, minor: 0, patch: 0),
        IOSRelease(major: 17, minor: 0, patch: 1),
        IOSRelease(major: 17, minor: 0, patch: 2),
        IOSRelease(major: 17, minor: 0, patch: 3),
        IOSRelease(major: 17, minor: 1, patch: 0),
        IOSRelease(major: 17, minor: 1, patch: 1),
        IOSRelease(major: 17, minor: 1, patch: 2),
        IOSRelease(major: 17, minor: 2, patch: 0),
        IOSRelease(major: 17, minor: 2, patch: 1),
        IOSRelease(major: 17, minor: 3, patch: 0),
        IOSRelease(major: 17, minor: 3, patch: 1),
        IOSRelease(major: 17, minor: 4, patch: 0),
        IOSRelease(major: 17, minor: 4, patch: 1),
        IOSRelease(major: 17, minor: 5, patch: 0),
        IOSRelease(major: 17, minor: 5, patch: 1),
        IOSRelease(major: 17, minor: 6, patch: 0),
        IOSRelease(major: 17, minor: 6, patch: 1),
        IOSRelease(major: 17, minor: 7, patch: 0),
        IOSRelease(major: 17, minor: 7, patch: 1),
        IOSRelease(major: 17, minor: 7, patch: 2),
        IOSRelease(major: 18, minor: 0, patch: 0),
        IOSRelease(major: 18, minor: 0, patch: 1),
        IOSRelease(major: 18, minor: 1, patch: 0),
        IOSRelease(major: 18, minor: 1, patch: 1),
        IOSRelease(major: 18, minor: 2, patch: 0),
        IOSRelease(major: 18, minor: 2, patch: 1),
        IOSRelease(major: 18, minor: 3, patch: 0),
        IOSRelease(major: 18, minor: 3, patch: 1),
        IOSRelease(major: 18, minor: 3, patch: 2),
        IOSRelease(major: 18, minor: 4, patch: 0),
        IOSRelease(major: 18, minor: 4, patch: 1),
        IOSRelease(major: 18, minor: 5, patch: 0),
        IOSRelease(major: 18, minor: 6, patch: 0),
        IOSRelease(major: 18, minor: 6, patch: 1),
        IOSRelease(major: 18, minor: 6, patch: 2),
        IOSRelease(major: 18, minor: 7, patch: 0)
    ]

    // Chrome values come from Google's iOS stable VersionHistory API.
    private static let chromeVersions = [
        "152.0.7977.64", "152.0.7977.53", "152.0.7977.40",
        "151.0.7922.112", "151.0.7922.105", "151.0.7922.57", "151.0.7922.43", "151.0.7922.25",
        "150.0.7871.113", "150.0.7871.51", "150.0.7871.34",
        "149.0.7827.137", "149.0.7827.45", "149.0.7827.26",
        "148.0.7778.166", "148.0.7778.100", "148.0.7778.47",
        "147.0.7727.99", "147.0.7727.47", "147.0.7727.22",
        "146.0.7680.151", "146.0.7680.40", "146.0.7680.38", "146.0.7680.24",
        "145.0.7632.108", "145.0.7632.55", "145.0.7632.41", "145.0.7632.34",
        "144.0.7559.95", "144.0.7559.85", "144.0.7559.53",
        "143.0.7499.151", "143.0.7499.108", "143.0.7499.92", "143.0.7499.38",
        "142.0.7444.148", "142.0.7444.128", "142.0.7444.77", "142.0.7444.46",
        "141.0.7390.96", "141.0.7390.69", "141.0.7390.41", "141.0.7390.26",
        "140.0.7339.122", "140.0.7339.101", "140.0.7339.95", "140.0.7339.39"
    ]

    // Firefox values come from Mozilla's firefox-ios release tags.
    private static let firefoxVersions = [
        "155.0", "154.1", "154.0",
        "153.3", "153.2", "153.1", "153.0",
        "152.4", "152.3", "152.1.2", "152.1.1", "152.1", "152.0",
        "151.3.2", "151.3", "151.2", "151.1", "151.0",
        "150.3", "150.2", "150.1", "150.0",
        "149.3", "149.2", "149.1", "149.0",
        "148.3", "148.2", "148.1", "148.0",
        "147.5", "147.4", "147.3", "147.2.1", "147.2", "147.1", "147.0",
        "146.1", "146.0",
        "145.3", "145.2", "145.1", "145.0",
        "144.3", "144.2", "144.1", "144.0"
    ]

    // These families have smaller public histories. Their current App Store
    // version is combined with the audited iOS releases instead of inventing
    // arbitrary version segments.
    private static let browserVersions: [String: [String]] = [
        "UC": ["12.2.1.1264"],
        "Via": ["1.9.0"],
        "Edge": ["152.0.4191.53", "141.0.3537.32", "140.0.3485.77"],
        "Chrome": chromeVersions,
        "Alook": ["23.0"],
        "Firefox": firefoxVersions,
        "Opera": ["6.7.1"]
    ]

    private static let minimumIOSMajorByBrowser: [String: Int] = [
        "Edge": 18,
        "Chrome": 18
    ]

    static func candidates(
        for browserName: String,
        maximumOSVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) -> [String] {
        let releases = availableIOSReleases(upTo: maximumOSVersion)

        switch browserName {
        case "iPhone Safari":
            return releases.map { makeSafari(release: $0, device: "iPhone") }
        case "iPad Safari":
            return releases.map { makeSafari(release: $0, device: "iPad") }
        default:
            guard let versions = browserVersions[browserName] else { return [] }
            let minimumIOSMajor = minimumIOSMajorByBrowser[browserName] ?? 17
            return releases.filter { $0.major >= minimumIOSMajor }.flatMap { release in
                versions.compactMap { version in
                    makeThirdPartyBrowser(
                        named: browserName,
                        browserVersion: version,
                        release: release
                    )
                }
            }
        }
    }

    static func browserName(for userAgent: String?) -> String {
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

    static func details(for userAgent: String) -> UserAgentDetails? {
        let deviceName: String
        let osVersion: String

        if let value = substring(
            in: userAgent,
            after: "CPU iPhone OS ",
            before: " like Mac OS X"
        ) {
            deviceName = "iPhone"
            osVersion = value.replacingOccurrences(of: "_", with: ".")
        } else if let value = substring(
            in: userAgent,
            after: "CPU OS ",
            before: " like Mac OS X"
        ) {
            deviceName = "iPad"
            osVersion = value.replacingOccurrences(of: "_", with: ".")
        } else {
            return nil
        }

        let browserName = browserName(for: userAgent)
        let browserVersion: String?
        switch browserName {
        case "UC": browserVersion = token(in: userAgent, after: "UCBrowser/")
        case "Via": browserVersion = token(in: userAgent, after: "Via/")
        case "Edge": browserVersion = token(in: userAgent, after: "EdgiOS/")
        case "Chrome": browserVersion = token(in: userAgent, after: "CriOS/")
        case "Alook": browserVersion = token(in: userAgent, after: "Alook/")
        case "Firefox": browserVersion = token(in: userAgent, after: "FxiOS/")
        case "Opera": browserVersion = token(in: userAgent, after: "OPiOS/")
        default: browserVersion = nil
        }

        return UserAgentDetails(
            browserName: browserName,
            deviceName: deviceName,
            operatingSystemVersion: osVersion,
            browserVersion: browserVersion
        )
    }

    private static func availableIOSReleases(
        upTo maximumOSVersion: OperatingSystemVersion
    ) -> [IOSRelease] {
        let maximumRelease = IOSRelease(
            major: maximumOSVersion.majorVersion,
            minor: maximumOSVersion.minorVersion,
            patch: maximumOSVersion.patchVersion
        )
        var releases = auditedIOSReleases.filter {
            $0.numericValue <= maximumRelease.numericValue
        }

        if maximumRelease.major >= 17,
           !releases.contains(maximumRelease) {
            releases.append(maximumRelease)
        }
        return releases.sorted { $0.numericValue < $1.numericValue }
    }

    private static func makeSafari(release: IOSRelease, device: String) -> String {
        "\(iosPrefix(release, device: device)) Version/\(release.safariVersion) Mobile/15E148 Safari/604.1"
    }

    private static func makeThirdPartyBrowser(
        named browserName: String,
        browserVersion: String,
        release: IOSRelease
    ) -> String? {
        let prefix = iosPrefix(release, device: "iPhone")
        switch browserName {
        case "UC":
            return "\(prefix) Mobile/15E148 Safari/604.1 UCBrowser/\(browserVersion)"
        case "Via":
            return "\(prefix) Version/\(release.safariVersion) Mobile/15E148 Safari/604.1 Via/\(browserVersion)"
        case "Edge":
            return "\(prefix) EdgiOS/\(browserVersion) Mobile/15E148 Safari/605.1.15"
        case "Chrome":
            return "\(prefix) CriOS/\(browserVersion) Mobile/15E148 Safari/604.1"
        case "Alook":
            return "\(prefix) Version/\(release.safariVersion) Mobile/15E148 Safari/604.1 Alook/\(browserVersion)"
        case "Firefox":
            return "\(prefix) FxiOS/\(browserVersion) Mobile/15E148 Safari/605.1.15"
        case "Opera":
            return "\(prefix) Version/\(release.safariVersion) Mobile/15E148 Safari/604.1 OPiOS/\(browserVersion)"
        default:
            return nil
        }
    }

    private static func iosPrefix(_ release: IOSRelease, device: String) -> String {
        if device == "iPad" {
            return "Mozilla/5.0 (iPad; CPU OS \(release.userAgentVersion) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko)"
        }
        return "Mozilla/5.0 (iPhone; CPU iPhone OS \(release.userAgentVersion) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko)"
    }

    private static func substring(
        in value: String,
        after prefix: String,
        before suffix: String
    ) -> String? {
        guard let prefixRange = value.range(of: prefix) else { return nil }
        let remainder = value[prefixRange.upperBound...]
        guard let suffixRange = remainder.range(of: suffix) else { return nil }
        return String(remainder[..<suffixRange.lowerBound])
    }

    private static func token(in value: String, after marker: String) -> String? {
        guard let markerRange = value.range(of: marker) else { return nil }
        let remainder = value[markerRange.upperBound...]
        let token = remainder.prefix { !$0.isWhitespace }
        return token.isEmpty ? nil : String(token)
    }
}
