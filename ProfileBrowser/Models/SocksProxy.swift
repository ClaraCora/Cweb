import Foundation

/// The URL schemes accepted by the proxy importer. All three schemes use
/// the SOCKS5 wire protocol; `socks5h` only indicates that hostname
/// resolution should happen through the proxy.
enum SocksProxyScheme: String, Codable, CaseIterable, Hashable, Sendable {
    case socks
    case socks5
    case socks5h
}

enum SocksProxyStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case untested
    case available
    case unavailable
}

struct SocksProxy: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var scheme: SocksProxyScheme
    var host: String
    var port: Int
    var username: String?
    var password: String?
    var latencyMilliseconds: Int?
    var status: SocksProxyStatus
    var lastCheckedAt: Date?
    var validationMessage: String?
    /// A redacted source value retained for editing and display. Passwords
    /// are intentionally omitted from this value.
    var sourceURLString: String?

    init(
        id: UUID = UUID(),
        scheme: SocksProxyScheme = .socks5,
        host: String,
        port: Int,
        username: String? = nil,
        password: String? = nil,
        latencyMilliseconds: Int? = nil,
        status: SocksProxyStatus = .untested,
        lastCheckedAt: Date? = nil,
        validationMessage: String? = nil,
        sourceURLString: String? = nil
    ) {
        self.id = id
        self.scheme = scheme
        self.host = Self.normalizeHost(host)
        self.port = port
        self.username = username
        self.password = password
        self.latencyMilliseconds = latencyMilliseconds
        self.status = status
        self.lastCheckedAt = lastCheckedAt
        self.validationMessage = validationMessage
        self.sourceURLString = sourceURLString
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case scheme
        case host
        case port
        case username
        case latencyMilliseconds
        case status
        case lastCheckedAt
        case validationMessage
        case sourceURLString
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        scheme = try container.decodeIfPresent(SocksProxyScheme.self, forKey: .scheme) ?? .socks5
        host = Self.normalizeHost(try container.decode(String.self, forKey: .host))
        port = try container.decode(Int.self, forKey: .port)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        // Passwords are kept in the keychain by SocksProxyRepository and are
        // intentionally absent from the JSON representation.
        password = nil
        latencyMilliseconds = try container.decodeIfPresent(Int.self, forKey: .latencyMilliseconds)
        status = try container.decodeIfPresent(SocksProxyStatus.self, forKey: .status) ?? .untested
        lastCheckedAt = try container.decodeIfPresent(Date.self, forKey: .lastCheckedAt)
        validationMessage = try container.decodeIfPresent(String.self, forKey: .validationMessage)
        sourceURLString = try container.decodeIfPresent(String.self, forKey: .sourceURLString)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(scheme, forKey: .scheme)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encodeIfPresent(username, forKey: .username)
        try container.encodeIfPresent(latencyMilliseconds, forKey: .latencyMilliseconds)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(lastCheckedAt, forKey: .lastCheckedAt)
        try container.encodeIfPresent(validationMessage, forKey: .validationMessage)
        try container.encodeIfPresent(sourceURLString, forKey: .sourceURLString)
    }

    /// Parses one `socks://`, `socks5://`, or `socks5h://` value. For
    /// convenience, bare `host:port` and `[ipv6]:port` values are treated as
    /// SOCKS5 endpoints, which is common in text feeds.
    init(urlString: String, id: UUID = UUID()) throws {
        let raw = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw SocksProxyParseError.emptyValue }

        let hasScheme = raw.range(of: "://") != nil
        let candidate = hasScheme ? raw : "socks5://\(raw)"
        guard let components = URLComponents(string: candidate),
              let schemeValue = components.scheme?.lowercased(),
              let scheme = SocksProxyScheme(rawValue: schemeValue)
        else {
            throw SocksProxyParseError.unsupportedScheme
        }

        guard let rawHost = components.host else {
            throw SocksProxyParseError.missingHost
        }
        let decodedHost = (rawHost.removingPercentEncoding ?? rawHost)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard !decodedHost.isEmpty else { throw SocksProxyParseError.missingHost }

        guard let port = components.port else {
            if Self.hasExplicitPort(in: candidate) {
                throw SocksProxyParseError.invalidPort
            }
            throw SocksProxyParseError.missingPort
        }
        guard (1...65_535).contains(port) else {
            throw SocksProxyParseError.invalidPort
        }

        let username = Self.decodeComponent(components.user)
        let password = Self.decodeComponent(components.password)
        guard components.path.isEmpty || components.path == "/" else {
            throw SocksProxyParseError.invalidValue
        }
        guard components.query == nil, components.fragment == nil else {
            throw SocksProxyParseError.invalidValue
        }

        let redactedSource = Self.redactedURL(
            scheme: scheme,
            host: decodedHost,
            port: port,
            username: username
        )
        self.init(
            id: id,
            scheme: scheme,
            host: decodedHost,
            port: port,
            username: username,
            password: password,
            sourceURLString: redactedSource
        )
    }

    /// A stable endpoint key useful for de-duplicating feed imports. It does
    /// not contain the password and therefore is safe to use in UI state.
    var identityKey: String {
        "\(Self.normalizeHost(host).lowercased())|\(port)|\(username ?? "")"
    }

    var displayAddress: String {
        Self.redactedURL(scheme: scheme, host: Self.normalizeHost(host), port: port, username: username)
    }

    var isAvailable: Bool { status == .available }

    var latency: Int? { latencyMilliseconds }

    var isValidated: Bool { status != .untested }

    var validationStatus: SocksProxyStatus {
        get { status }
        set { status = newValue }
    }

    func applying(_ result: SocksProxyValidationResult) -> SocksProxy {
        guard result.proxyID == id else { return self }
        var copy = self
        copy.latencyMilliseconds = result.latencyMilliseconds
        copy.status = result.status
        copy.lastCheckedAt = result.checkedAt
        copy.validationMessage = result.message
        return copy
    }

    private static func decodeComponent(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value.removingPercentEncoding ?? value
    }

    /// Network APIs expect an IPv6 host without URL-style brackets. Keep the
    /// stored value canonical so values entered manually behave like imported
    /// URL values and deduplication remains consistent.
    static func normalizeHost(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2,
              trimmed.first == "[",
              trimmed.last == "]" else {
            return trimmed
        }
        return String(trimmed.dropFirst().dropLast())
    }

    private static func hasExplicitPort(in value: String) -> Bool {
        guard let separator = value.range(of: "://") else { return false }
        let authorityStart = separator.upperBound
        let authority = value[authorityStart...].split(separator: "/", maxSplits: 1).first ?? ""
        let hostPort = authority.split(separator: "@", maxSplits: 1).last ?? authority
        if hostPort.first == "[" {
            guard let closingBracket = hostPort.firstIndex(of: "]") else { return false }
            let nextIndex = hostPort.index(after: closingBracket)
            return nextIndex < hostPort.endIndex && hostPort[nextIndex] == ":"
        }
        return hostPort.lastIndex(of: ":") != nil
    }

    private static func redactedURL(
        scheme: SocksProxyScheme,
        host: String,
        port: Int,
        username: String?
    ) -> String {
        let normalizedHost = normalizeHost(host)
        let hostPart = normalizedHost.contains(":") ? "[\(normalizedHost)]" : normalizedHost
        let userPart: String
        if let username, !username.isEmpty {
            let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? username
            userPart = "\(encoded)@"
        } else {
            userPart = ""
        }
        return "\(scheme.rawValue)://\(userPart)\(hostPart):\(port)"
    }
}

enum SocksProxyParseError: LocalizedError, Equatable, Sendable {
    case emptyValue
    case unsupportedScheme
    case missingHost
    case missingPort
    case invalidPort
    case invalidValue

    var errorDescription: String? {
        switch self {
        case .emptyValue:
            return "代理地址不能为空。"
        case .unsupportedScheme:
            return "仅支持 socks://、socks5:// 或 socks5h:// 地址。"
        case .missingHost:
            return "代理地址缺少主机名。"
        case .missingPort:
            return "代理地址缺少端口。"
        case .invalidPort:
            return "代理端口必须在 1 到 65535 之间。"
        case .invalidValue:
            return "代理地址包含无法识别的路径或参数。"
        }
    }
}

struct SocksProxyParser {
    private init() {}

    static func parse(_ value: String) throws -> SocksProxy {
        try SocksProxy(urlString: value)
    }

    /// Parses newline, comma, or whitespace separated feed content. Blank
    /// lines and `#`/`//` comments are ignored. By default malformed lines are
    /// skipped so one bad item does not discard a whole remote feed.
    static func parseList(_ content: String, ignoringInvalid: Bool = true) throws -> [SocksProxy] {
        var values: [String] = []
        for rawLine in content.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            var line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("//") else { continue }
            if let commentStart = line.firstIndex(of: "#") {
                line = String(line[..<commentStart])
            }
            values.append(contentsOf: line
                .split(whereSeparator: { $0.isWhitespace || $0 == "," })
                .map(String.init))
        }

        var result: [SocksProxy] = []
        var seen = Set<String>()
        for value in values {
            do {
                let proxy = try parse(value)
                guard seen.insert(proxy.identityKey).inserted else { continue }
                result.append(proxy)
            } catch {
                if !ignoringInvalid { throw error }
            }
        }
        return result
    }
}

extension SocksProxy {
    static func parse(_ value: String) throws -> SocksProxy {
        try SocksProxy(urlString: value)
    }

    static func parse(url: URL) throws -> SocksProxy {
        try SocksProxy(urlString: url.absoluteString)
    }
}

struct SocksProxyPreset: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var url: URL
    var isEnabled: Bool
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String = "",
        url: URL,
        isEnabled: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.url = url
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (url.host ?? url.absoluteString) : trimmed
    }
}
