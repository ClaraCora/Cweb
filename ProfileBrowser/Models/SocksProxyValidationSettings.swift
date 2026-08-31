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
    static let defaults = SocksProxyValidationSettings()

    /// If true, batch validation discards unavailable and untested records.
    var retainOnlyAvailable: Bool
    /// Maximum number of records retained after a batch validation. Zero means
    /// unlimited. The default preserves the historical top-30 behavior.
    var maxRetainedCount: Int
    var sortMode: SocksProxySortMode
    var targetHost: String
    var targetPort: Int
    var verifiesTLS: Bool
    var timeoutSeconds: Int
    var maxConcurrent: Int

    init(
        retainOnlyAvailable: Bool = true,
        maxRetainedCount: Int = 30,
        sortMode: SocksProxySortMode = .latencyAscending,
        targetHost: String = "example.com",
        targetPort: Int = 443,
        verifiesTLS: Bool = true,
        timeoutSeconds: Int = 8,
        maxConcurrent: Int = 8
    ) {
        self.retainOnlyAvailable = retainOnlyAvailable
        self.maxRetainedCount = maxRetainedCount
        self.sortMode = sortMode
        self.targetHost = targetHost
        self.targetPort = targetPort
        self.verifiesTLS = verifiesTLS
        self.timeoutSeconds = timeoutSeconds
        self.maxConcurrent = maxConcurrent
    }

    private enum CodingKeys: String, CodingKey {
        case retainOnlyAvailable
        case maxRetainedCount
        case sortMode
        case targetHost
        case targetPort
        case verifiesTLS
        case timeoutSeconds
        case maxConcurrent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            retainOnlyAvailable: try container.decodeIfPresent(Bool.self, forKey: .retainOnlyAvailable) ?? true,
            maxRetainedCount: try container.decodeIfPresent(Int.self, forKey: .maxRetainedCount) ?? 30,
            sortMode: try container.decodeIfPresent(SocksProxySortMode.self, forKey: .sortMode) ?? .latencyAscending,
            targetHost: try container.decodeIfPresent(String.self, forKey: .targetHost) ?? "example.com",
            targetPort: try container.decodeIfPresent(Int.self, forKey: .targetPort) ?? 443,
            verifiesTLS: try container.decodeIfPresent(Bool.self, forKey: .verifiesTLS) ?? true,
            timeoutSeconds: try container.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? 8,
            maxConcurrent: try container.decodeIfPresent(Int.self, forKey: .maxConcurrent) ?? 8
        )
    }

    /// Sanitizes values loaded from disk or entered in a form before they are
    /// used by networking code. This keeps malformed persisted settings from
    /// turning into an invalid URL or an unbounded worker pool.
    var normalized: SocksProxyValidationSettings {
        var value = self
        value.maxRetainedCount = min(500, max(0, maxRetainedCount))

        let host = targetHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.isEmpty
            || host.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
            || host.contains(where: { "/?#".contains($0) }) {
            value.targetHost = Self.defaults.targetHost
        } else {
            value.targetHost = String(host.prefix(253))
        }

        value.targetPort = min(65_535, max(1, targetPort))
        value.timeoutSeconds = min(60, max(1, timeoutSeconds))
        value.maxConcurrent = min(32, max(1, maxConcurrent))
        return value
    }

    var validationConfiguration: SocksProxyValidationConfiguration {
        let value = normalized
        return SocksProxyValidationConfiguration(
            timeout: TimeInterval(value.timeoutSeconds),
            targetHost: value.targetHost,
            targetPort: value.targetPort,
            verifiesTLS: value.verifiesTLS
        )
    }
}
