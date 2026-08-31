import Foundation

/// Persists SOCKS proxy records and the user-maintained feed presets.
/// Proxies and presets live in separate files so clearing one collection
/// cannot accidentally remove the other.
struct SocksProxyRepository {
    private let fileManager: FileManager
    private let fileURL: URL
    private let presetsFileURL: URL
    private let settingsFileURL: URL
    private let credentialStore: SocksProxyCredentialStore

    init(
        fileManager: FileManager = .default,
        fileURL: URL? = nil,
        presetsFileURL: URL? = nil,
        settingsFileURL: URL? = nil,
        credentialStore: SocksProxyCredentialStore = SocksProxyCredentialStore()
    ) {
        self.fileManager = fileManager

        let baseURL: URL
        if let fileURL {
            self.fileURL = fileURL
            baseURL = fileURL.deletingLastPathComponent()
        } else {
            baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appending(path: "ProfileBrowser", directoryHint: .isDirectory)
            self.fileURL = baseURL.appending(path: "socks-proxies.json", directoryHint: .notDirectory)
        }

        self.presetsFileURL = presetsFileURL
            ?? baseURL.appending(path: "socks-proxy-presets.json", directoryHint: .notDirectory)
        self.settingsFileURL = settingsFileURL
            ?? baseURL.appending(path: "socks-proxy-settings.json", directoryHint: .notDirectory)
        self.credentialStore = credentialStore
    }

    func load() throws -> [SocksProxy] {
        let persisted: [SocksProxy] = try loadArray(from: fileURL)
        return try persisted.map { proxy in
            var value = proxy
            value.password = try credentialStore.password(for: proxy.id)
            return value
        }
    }

    func save(_ proxies: [SocksProxy]) throws {
        let previousIDs: Set<UUID>
        if fileManager.fileExists(atPath: fileURL.path),
           let previous: [SocksProxy] = try? loadArray(from: fileURL) {
            previousIDs = Set(previous.map(\.id))
        } else {
            previousIDs = []
        }

        try saveArray(proxies, to: fileURL)
        for proxy in proxies {
            try credentialStore.save(password: proxy.password, for: proxy.id)
        }
        let currentIDs = Set(proxies.map(\.id))
        for removedID in previousIDs.subtracting(currentIDs) {
            try credentialStore.delete(for: removedID)
        }
    }

    @discardableResult
    func upsert(_ proxy: SocksProxy) throws -> [SocksProxy] {
        var proxies = try load()
        if let index = proxies.firstIndex(where: { $0.id == proxy.id }) {
            proxies[index] = proxy
        } else {
            proxies.append(proxy)
        }
        try save(proxies)
        return proxies
    }

    /// Replaces all records in one atomic write. The empty array is valid and
    /// is used by the batch-clear action in the management screen.
    func removeAll() throws {
        try save([])
    }

    func loadPresets() throws -> [SocksProxyPreset] {
        try loadArray(from: presetsFileURL)
    }

    func savePresets(_ presets: [SocksProxyPreset]) throws {
        try saveArray(presets, to: presetsFileURL)
    }

    func loadSettings() throws -> SocksProxyValidationSettings {
        guard fileManager.fileExists(atPath: settingsFileURL.path) else {
            return .defaults
        }
        let value: SocksProxyValidationSettings = try loadValue(from: settingsFileURL)
        return value.normalized
    }

    func saveSettings(_ settings: SocksProxyValidationSettings) throws {
        try saveValue(settings.normalized, to: settingsFileURL)
    }

    @discardableResult
    func upsertPreset(_ preset: SocksProxyPreset) throws -> [SocksProxyPreset] {
        var presets = try loadPresets()
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
        } else {
            presets.append(preset)
        }
        try savePresets(presets)
        return presets
    }

    func removeAllPresets() throws {
        try savePresets([])
    }

    func delete(proxyID: UUID) throws {
        var proxies = try load()
        proxies.removeAll { $0.id == proxyID }
        try save(proxies)
    }

    func delete(presetID: UUID) throws {
        var presets = try loadPresets()
        presets.removeAll { $0.id == presetID }
        try savePresets(presets)
    }

    /// Inserts new records while retaining the supplied order and existing
    /// records. A repeated endpoint refreshes its content in place, keeping
    /// the record ID so management actions remain predictable while volatile
    /// display numbers can point at the refreshed value.
    @discardableResult
    func appendUnique(_ newProxies: [SocksProxy]) throws -> [SocksProxy] {
        var proxies = try load()
        for proxy in newProxies {
            if let index = proxies.firstIndex(where: { $0.identityKey == proxy.identityKey }) {
                let existing = proxies[index]
                let contentChanged = existing.scheme != proxy.scheme
                    || existing.host.caseInsensitiveCompare(proxy.host) != .orderedSame
                    || existing.port != proxy.port
                    || existing.username != proxy.username
                    || existing.password != proxy.password
                guard contentChanged else { continue }
                var refreshed = SocksProxy(
                    id: existing.id,
                    scheme: proxy.scheme,
                    host: proxy.host,
                    port: proxy.port,
                    username: proxy.username,
                    password: proxy.password,
                    sourceURLString: proxy.sourceURLString
                )
                // A feed refresh represents a new endpoint state, so force a
                // fresh validation rather than displaying stale latency.
                refreshed.latencyMilliseconds = nil
                refreshed.status = .untested
                refreshed.lastCheckedAt = nil
                refreshed.validationMessage = nil
                proxies[index] = refreshed
            } else {
                proxies.append(proxy)
            }
        }
        try save(proxies)
        return proxies
    }

    /// Merges a refreshed feed. Existing endpoint identities are replaced in
    /// place (while retaining their internal record ID), so a changed
    /// credential or scheme is immediately reflected without growing stale
    /// duplicates. New endpoints are appended.
    @discardableResult
    func mergeRefreshing(_ refreshedProxies: [SocksProxy]) throws -> [SocksProxy] {
        var proxies = try load()
        var indexByIdentity: [String: Int] = [:]
        for (index, proxy) in proxies.enumerated() {
            indexByIdentity[proxy.identityKey] = index
        }

        for refreshed in refreshedProxies {
            if let index = indexByIdentity[refreshed.identityKey] {
                let existing = proxies[index]
                proxies[index] = SocksProxy(
                    id: existing.id,
                    scheme: refreshed.scheme,
                    host: refreshed.host,
                    port: refreshed.port,
                    username: refreshed.username,
                    password: refreshed.password ?? existing.password,
                    latencyMilliseconds: nil,
                    status: .untested,
                    lastCheckedAt: nil,
                    validationMessage: nil,
                    sourceURLString: refreshed.sourceURLString
                )
            } else {
                indexByIdentity[refreshed.identityKey] = proxies.count
                proxies.append(refreshed)
            }
        }
        try save(proxies)
        return proxies
    }

    private func loadArray<T: Decodable>(from url: URL) throws -> [T] {
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        return try loadValue(from: url)
    }

    private func loadValue<T: Decodable>(from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try Self.decoder.decode(T.self, from: data)
    }

    private func saveArray<T: Encodable>(_ values: [T], to url: URL) throws {
        try saveValue(values, to: url)
    }

    private func saveValue<T: Encodable>(_ value: T, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(value)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
