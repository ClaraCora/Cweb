import CryptoKit
import Foundation

/// A decoded archive is a value only. Decryption never writes to Keychain.
struct BackupArchive: Codable, Sendable {
    var profiles: [BrowserProfile]
    var credentials: [StoredCredential]
    var proxies: [BackupProxy]?
    var bindings: [BackupProxyBinding]?
    var presets: [SocksProxyPreset]?
    var proxySettings: SocksProxyValidationSettings?
    var scriptSettings: GlobalScriptSettings?
    var appearance: String?
}

struct BackupProxy: Codable, Sendable {
    var proxy: SocksProxy
    // SocksProxy's normal disk encoding intentionally excludes this value.
    var password: String?
}

struct BackupProxyBinding: Codable, Sendable {
    let profileID: UUID
    let proxyID: UUID
}

struct BackupRestorePlan {
    var baseProxies: [SocksProxy]
    var baseProfiles: [BrowserProfile]
    var basePresets: [SocksProxyPreset]
    var baseSettings: SocksProxyValidationSettings
    var baseScript: GlobalScriptSettings
    var profiles: [BrowserProfile]
    var credentials: [StoredCredential]
    var proxies: [SocksProxy]
    var presets: [SocksProxyPreset]
    var archive: BackupArchive
    var warnings: [String]
    var newProxyCount: Int
}

@MainActor
struct BackupService {
    nonisolated static let maximumFileSize = 32 * 1024 * 1024
    nonisolated private static let saltLength = 16
    private let vault: CredentialVault

    init(vault: CredentialVault) { self.vault = vault }

    func snapshot(profiles: [BrowserProfile]) throws -> BackupArchive {
        let credentials = try profiles.flatMap { try vault.credentials(profileID: $0.id) }
        return BackupArchive(profiles: profiles, credentials: credentials)
    }

    // Kept for callers exporting an environment-only v1 archive.
    func export(profiles: [BrowserProfile], password: String) throws -> Data {
        try Self.encrypt(snapshot(profiles: profiles), password: password)
    }

    /// Legacy convenience API now has no persistence side effects.
    func importProfiles(from data: Data, password: String) throws -> [BrowserProfile] {
        try Self.decrypt(data, password: password).profiles
    }

    nonisolated static func background<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        let task = Task.detached(priority: .userInitiated, operation: work)
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    nonisolated static func encrypt(_ archive: BackupArchive, password: String) throws -> Data {
        try validatePassword(password)
        try Task.checkCancellation()
        let plaintext = try JSONEncoder.backup.encode(archive)
        guard plaintext.count <= maximumFileSize / 2 else { throw BackupError.fileTooLarge }
        let salt = Data((0..<saltLength).map { _ in UInt8.random(in: .min ... .max) })
        let iterations = 120_000
        let key = try deriveKey(password: password, salt: salt, iterations: iterations)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw BackupError.encryptionFailed }
        let envelope = BackupEnvelope(version: 2, iterations: iterations, salt: salt.base64EncodedString(), sealedData: combined.base64EncodedString())
        return try JSONEncoder.backup.encode(envelope)
    }

    nonisolated static func decrypt(_ data: Data, password: String) throws -> BackupArchive {
        try validatePassword(password)
        let envelope = try decodeEnvelope(from: data)
        let key = try deriveKey(password: password, salt: envelope.salt, iterations: envelope.iterations)
        try Task.checkCancellation()
        let plaintext: Data
        do { plaintext = try AES.GCM.open(envelope.sealedBox, using: key) }
        catch { throw BackupError.invalidPassword }
        var archive: BackupArchive
        do { archive = try JSONDecoder.backup.decode(BackupArchive.self, from: plaintext) }
        catch { throw BackupError.invalidFormat }
        let ids = Set(archive.profiles.map(\.id))
        let proxyIDs = Set((archive.proxies ?? []).map { $0.proxy.id })
        guard ids.count == archive.profiles.count,
              Set(archive.credentials.map(\.id)).count == archive.credentials.count,
              proxyIDs.count == (archive.proxies ?? []).count,
              archive.credentials.allSatisfy({ ids.contains($0.profileID) }),
              (archive.bindings ?? []).allSatisfy({ ids.contains($0.profileID) && proxyIDs.contains($0.proxyID) }),
              Set((archive.bindings ?? []).map(\.profileID)).count == (archive.bindings ?? []).count,
              (archive.proxies ?? []).allSatisfy({ !$0.proxy.host.isEmpty && (1...65535).contains($0.proxy.port) }),
              archive.profiles.allSatisfy({ ["https", "http"].contains($0.homePage.scheme?.lowercased() ?? "") })
        else { throw BackupError.invalidFormat }
        // Fresh profile/store/credential IDs keep restores isolated from existing data.
        var idMap: [UUID: UUID] = [:]
        archive.profiles = archive.profiles.map { original in
            let id = UUID()
            idMap[original.id] = id
            return BrowserProfile(id: id, name: original.name, groupName: original.groupName,
                groupCode: original.groupCode, groupEmoji: original.groupEmoji, groupSortOrder: original.groupSortOrder,
                userAgent: original.userAgent, homePage: original.homePage, color: original.color,
                socksProxyNumber: original.socksProxyNumber, unresolvedProxyNumber: original.unresolvedProxyNumber)
        }
        archive.credentials = archive.credentials.map { original in
            StoredCredential(profileID: idMap[original.profileID]!, origin: original.origin,
                username: original.username, password: original.password, label: original.label)
        }
        archive.bindings = archive.bindings?.map { BackupProxyBinding(profileID: idMap[$0.profileID]!, proxyID: $0.proxyID) }
        return archive
    }

    nonisolated static func validateBackupData(_ data: Data) throws { _ = try decodeEnvelope(from: data) }

    nonisolated private static func decodeEnvelope(from data: Data) throws -> (iterations: Int, salt: Data, sealedBox: AES.GCM.SealedBox) {
        guard data.count <= maximumFileSize else { throw BackupError.fileTooLarge }
        do {
            let envelope = try JSONDecoder.backup.decode(BackupEnvelope.self, from: data)
            guard (1...2).contains(envelope.version), (10_000...500_000).contains(envelope.iterations),
                  let salt = Data(base64Encoded: envelope.salt), salt.count == saltLength,
                  let combined = Data(base64Encoded: envelope.sealedData) else { throw BackupError.invalidFormat }
            return (envelope.iterations, salt, try AES.GCM.SealedBox(combined: combined))
        } catch { throw BackupError.invalidFormat }
    }

    nonisolated private static func validatePassword(_ password: String) throws {
        guard password.count >= 8 else { throw BackupError.passwordTooShort }
    }

    nonisolated private static func deriveKey(password: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        let passwordData = Data(password.utf8)
        var block = salt
        block.append(contentsOf: [0, 0, 0, 1])

        var u = Data(HMAC<SHA256>.authenticationCode(for: block, using: SymmetricKey(data: passwordData)))
        var result = u
        if iterations > 1 {
            for iteration in 1..<iterations {
                if iteration % 1024 == 0 { try Task.checkCancellation() }
                u = Data(HMAC<SHA256>.authenticationCode(for: u, using: SymmetricKey(data: passwordData)))
                for index in result.indices {
                    result[index] = result[index] ^ u[index]
                }
            }
        }
        return SymmetricKey(data: result)
    }
}

private struct BackupEnvelope: Codable {
    let version: Int
    let iterations: Int
    let salt: String
    let sealedData: String
}

private extension JSONEncoder {
    static var backup: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var backup: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum BackupError: LocalizedError, Equatable {
    case passwordTooShort, encryptionFailed, invalidFormat, invalidPassword, fileTooLarge, stateChanged, incompleteStore
    var errorDescription: String? {
        switch self {
        case .incompleteStore: "环境、代理或设置尚未完整读取，暂不能创建或恢复完整备份。请先重试读取数据。"
        case .stateChanged: "数据在预览后发生了变化，请重新解锁备份生成预览。"
        case .passwordTooShort: "备份密码至少需要 8 个字符。"
        case .encryptionFailed: "无法加密备份文件。"
        case .invalidFormat: "备份文件格式无效或已损坏。"
        case .invalidPassword: "备份密码不正确。"
        case .fileTooLarge: "备份文件超过 32 MB 上限，请选择较小的备份。"
        }
    }
}
