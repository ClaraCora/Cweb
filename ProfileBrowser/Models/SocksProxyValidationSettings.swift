import Foundation

/// The order used for the volatile display numbers in the SOCKS list.
/// Environment profiles store a number, so this setting intentionally affects
/// both the management list and profile selection consistently.
enum SocksProxySortMode: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case latencyAscending
    case inputOrder

    var id: Self { self }

    var title: String {
        switch self {
        case .latencyAscending:
            return "按延迟从低到高"
        case .inputOrder:
            return "保持导入顺序"
        }
    }

    var explanation: String {
        switch self {
        case .latencyAscending:
            return "可用代理优先，延迟较低的排在前面。"
        case .inputOrder:
            return "保留验证前的列表顺序，编号不会因延迟改变。"
        }
    }
}

/// User-controlled policy for batch SOCKS validation. Values are persisted in
/// a separate settings file so changing the policy never rewrites proxy
/// credentials or endpoint records.
struct SocksProxyValidationSettings: Codable, Hashable, Sendable {
    static let defaultTargetURLString = "https://example.com/"
    static let defaults = SocksProxyValidationSettings()

    /// If true, batch validation discards unavailable and untested records.
    var retainOnlyAvailable: Bool
    /// Maximum number of records retained after a batch validation. Zero means
    /// unlimited. The default preserves the historical top-30 behavior.
    var maxRetainedCount: Int
    var sortMode: SocksProxySortMode
    var targetURLString: String
    var verifiesTLS: Bool
    var timeoutSeconds: Int
    var maxConcurrent: Int

    init(
        retainOnlyAvailable: Bool = true,
        maxRetainedCount: Int = 30,
        sortMode: SocksProxySortMode = .latencyAscending,
        targetURLString: String = SocksProxyValidationSettings.defaultTargetURLString,
        verifiesTLS: Bool = true,
        timeoutSeconds: Int = 8,
        maxConcurrent: Int = 8
    ) {
        self.retainOnlyAvailable = retainOnlyAvailable
        self.maxRetainedCount = maxRetainedCount
        self.sortMode = sortMode
        self.targetURLString = targetURLString
        self.verifiesTLS = verifiesTLS
        self.timeoutSeconds = timeoutSeconds
        self.maxConcurrent = maxConcurrent
    }

    private enum CodingKeys: String, CodingKey {
        case retainOnlyAvailable
        case maxRetainedCount
        case sortMode
        case targetURLString
        // Retained for decoding settings written before full URL support.
        case targetHost
        case targetPort
        case verifiesTLS
        case timeoutSeconds
        case maxConcurrent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let targetURLString: String
        if let storedURL = try container.decodeIfPresent(String.self, forKey: .targetURLString) {
            targetURLString = storedURL
        } else {
            let host = try container.decodeIfPresent(String.self, forKey: .targetHost) ?? "example.com"
            let port = try container.decodeIfPresent(Int.self, forKey: .targetPort) ?? 443
            targetURLString = Self.legacyTargetURLString(host: host, port: port)
        }
        self.init(
            retainOnlyAvailable: try container.decodeIfPresent(Bool.self, forKey: .retainOnlyAvailable) ?? true,
            maxRetainedCount: try container.decodeIfPresent(Int.self, forKey: .maxRetainedCount) ?? 30,
            sortMode: try container.decodeIfPresent(SocksProxySortMode.self, forKey: .sortMode) ?? .latencyAscending,
            targetURLString: targetURLString,
            verifiesTLS: try container.decodeIfPresent(Bool.self, forKey: .verifiesTLS) ?? true,
            timeoutSeconds: try container.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? 8,
            maxConcurrent: try container.decodeIfPresent(Int.self, forKey: .maxConcurrent) ?? 8
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(retainOnlyAvailable, forKey: .retainOnlyAvailable)
        try container.encode(maxRetainedCount, forKey: .maxRetainedCount)
        try container.encode(sortMode, forKey: .sortMode)
        try container.encode(targetURLString, forKey: .targetURLString)
        try container.encode(verifiesTLS, forKey: .verifiesTLS)
        try container.encode(timeoutSeconds, forKey: .timeoutSeconds)
        try container.encode(maxConcurrent, forKey: .maxConcurrent)
    }

    /// Sanitizes values loaded from disk or entered in a form before they are
    /// used by networking code. This keeps malformed persisted settings from
    /// turning into an invalid URL or an unbounded worker pool.
    var normalized: SocksProxyValidationSettings {
        var value = self
        value.maxRetainedCount = min(500, max(0, maxRetainedCount))
        value.targetURLString = Self.targetURL(from: targetURLString)?.absoluteString
            ?? Self.defaultTargetURLString
        value.timeoutSeconds = min(60, max(1, timeoutSeconds))
        value.maxConcurrent = min(32, max(1, maxConcurrent))
        return value
    }

    var validationConfiguration: SocksProxyValidationConfiguration {
        let value = normalized
        return SocksProxyValidationConfiguration(
            timeout: TimeInterval(value.timeoutSeconds),
            targetURL: Self.targetURL(from: value.targetURLString),
            verifiesTLS: value.verifiesTLS
        )
    }

    static func targetURL(from rawValue: String) -> URL? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              value.count <= 2_048,
              value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              var components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              !host.isEmpty,
              host.count <= 253,
              components.user == nil,
              components.password == nil,
              components.fragment == nil else {
            return nil
        }
        if let port = components.port, !(1...65_535).contains(port) {
            return nil
        }
        components.scheme = "https"
        components.host = host.lowercased()
        if components.port == 443 {
            components.port = nil
        }
        if components.path.isEmpty {
            components.path = "/"
        }
        return components.url
    }

    private static func legacyTargetURLString(host: String, port: Int) -> String {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty,
              host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              !host.contains(where: { "/?#".contains($0) }) else {
            return defaultTargetURLString
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.port = port == 443 ? nil : min(65_535, max(1, port))
        components.path = "/"
        return components.url?.absoluteString ?? defaultTargetURLString
    }
}
