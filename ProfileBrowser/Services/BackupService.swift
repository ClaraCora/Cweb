import CryptoKit
import Foundation

@MainActor
struct BackupService {
    private static let formatVersion = 1
    private static let iterations = 120_000
    private static let saltLength = 16

    private let vault: CredentialVault

    init(vault: CredentialVault) {
        self.vault = vault
    }

    func export(profiles: [BrowserProfile], password: String) throws -> Data {
        try validatePassword(password)
        var credentials: [StoredCredential] = []
        for profile in profiles {
            credentials.append(contentsOf: try vault.credentials(profileID: profile.id))
        }

        let payload = BackupPayload(profiles: profiles, credentials: credentials)
        let plaintext = try JSONEncoder.backup.encode(payload)
        let salt = Data((0..<Self.saltLength).map { _ in UInt8.random(in: .min ... .max) })
        let key = deriveKey(password: password, salt: salt, iterations: Self.iterations)
        let sealedBox = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealedBox.combined else { throw BackupError.encryptionFailed }

        let envelope = BackupEnvelope(
            version: Self.formatVersion,
            iterations: Self.iterations,
            salt: salt.base64EncodedString(),
            sealedData: combined.base64EncodedString()
        )
        return try JSONEncoder.backup.encode(envelope)
    }

    func importProfiles(from data: Data, password: String) throws -> [BrowserProfile] {
        try validatePassword(password)
        let envelope = try JSONDecoder.backup.decode(BackupEnvelope.self, from: data)
        guard envelope.version == Self.formatVersion,
              envelope.iterations >= 10_000,
              envelope.iterations <= 500_000,
              let salt = Data(base64Encoded: envelope.salt),
              let combined = Data(base64Encoded: envelope.sealedData)
        else { throw BackupError.invalidFormat }

        let key = deriveKey(password: password, salt: salt, iterations: envelope.iterations)
        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.SealedBox(combined: combined)
        } catch {
            throw BackupError.invalidPassword
        }

        let plaintext: Data
        do {
            plaintext = try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw BackupError.invalidPassword
        }

        let payload: BackupPayload
        do {
            payload = try JSONDecoder.backup.decode(BackupPayload.self, from: plaintext)
        } catch {
            throw BackupError.invalidFormat
        }

        let validProfileIDs = Set(payload.profiles.map(\.id))
        guard payload.credentials.allSatisfy({ validProfileIDs.contains($0.profileID) }) else {
            throw BackupError.invalidFormat
        }

        var idMap: [UUID: UUID] = [:]
        let importedProfiles = payload.profiles.map { profile in
            let newID = UUID()
            idMap[profile.id] = newID
            return BrowserProfile(
                id: newID,
                name: profile.name,
                groupName: profile.groupName,
                websiteDataStoreID: UUID(),
                userAgent: profile.userAgent,
                fingerprintSeed: UUID(),
                homePage: profile.homePage,
                color: profile.color,
                createdAt: .now,
                updatedAt: .now,
                lastOpenedAt: nil
            )
        }

        for credential in payload.credentials {
            guard let newProfileID = idMap[credential.profileID] else { continue }
            let remapped = StoredCredential(
                id: UUID(),
                profileID: newProfileID,
                origin: credential.origin,
                username: credential.username,
                password: credential.password,
                label: credential.label,
                createdAt: .now,
                updatedAt: .now
            )
            try vault.save(remapped)
        }

        return importedProfiles
    }

    private func validatePassword(_ password: String) throws {
        guard password.count >= 8 else { throw BackupError.passwordTooShort }
    }

    private func deriveKey(password: String, salt: Data, iterations: Int) -> SymmetricKey {
        let passwordData = Data(password.utf8)
        var block = salt
        block.append(contentsOf: [0, 0, 0, 1])

        var u = Data(HMAC<SHA256>.authenticationCode(for: block, using: SymmetricKey(data: passwordData)))
        var result = u
        if iterations > 1 {
            for _ in 1..<iterations {
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

private struct BackupPayload: Codable {
    let profiles: [BrowserProfile]
    let credentials: [StoredCredential]
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

enum BackupError: LocalizedError {
    case passwordTooShort
    case encryptionFailed
    case invalidFormat
    case invalidPassword

    var errorDescription: String? {
        switch self {
        case .passwordTooShort:
            return "备份密码至少需要 8 个字符。"
        case .encryptionFailed:
            return "无法加密备份文件。"
        case .invalidFormat:
            return "备份文件格式无效或已损坏。"
        case .invalidPassword:
            return "备份密码不正确。"
        }
    }
}
