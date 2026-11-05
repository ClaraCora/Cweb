import Foundation
import Security

@MainActor
final class CredentialVault {
    private let servicePrefix = "com.personal.profilebrowser.credentials"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var inMemoryItems: [UUID: Data]?
    enum Mutation { case save(StoredCredential), delete(UUID), deleteAll(UUID) }
    private let beforeMutation: ((Mutation) throws -> Void)?

    init(inMemory: Bool = false, beforeMutation: ((Mutation) throws -> Void)? = nil) {
        inMemoryItems = inMemory ? [:] : nil
        self.beforeMutation = beforeMutation
    }

    func credentials(profileID: UUID, origin: WebOrigin? = nil) throws -> [StoredCredential] {
        if let inMemoryItems {
            return try inMemoryItems.values
                .map { try decoder.decode(StoredCredential.self, from: $0) }
                .filter { $0.profileID == profileID }
                .filter { credential in origin.map { $0 == credential.origin } ?? true }
                .sorted { lhs, rhs in
                    if lhs.label == rhs.label { return lhs.username < rhs.username }
                    return lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
                }
        }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service(for: profileID),
            kSecMatchLimit: kSecMatchLimitAll,
            kSecReturnData: true
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw KeychainError(status: status) }

        let dataItems: [Data]
        if let values = result as? [Data] {
            dataItems = values
        } else if let value = result as? Data {
            dataItems = [value]
        } else {
            throw KeychainError.invalidData
        }

        return try dataItems
            .map { try decoder.decode(StoredCredential.self, from: $0) }
            .filter { credential in origin.map { $0 == credential.origin } ?? true }
            .sorted { lhs, rhs in
                if lhs.label == rhs.label { return lhs.username < rhs.username }
                return lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
            }
    }

    func save(_ credential: StoredCredential) throws {
        try beforeMutation?(.save(credential))
        let data = try encoder.encode(credential)
        if inMemoryItems != nil {
            inMemoryItems![credential.id] = data
            return
        }

        let identity: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service(for: credential.profileID),
            kSecAttrAccount: credential.id.uuidString
        ]
        let updates: [CFString: Any] = [kSecValueData: data]

        let updateStatus = SecItemUpdate(identity as CFDictionary, updates as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw KeychainError(status: updateStatus) }

        var item = identity
        item[kSecValueData] = data
        item[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
    }

    func delete(_ credential: StoredCredential) throws {
        try beforeMutation?(.delete(credential.id))
        if inMemoryItems != nil {
            inMemoryItems!.removeValue(forKey: credential.id)
            return
        }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service(for: credential.profileID),
            kSecAttrAccount: credential.id.uuidString
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    func deleteAll(profileID: UUID) throws {
        try beforeMutation?(.deleteAll(profileID))
        if inMemoryItems != nil {
            let matchingIDs = try inMemoryItems!.compactMap { id, data -> UUID? in
                let credential = try decoder.decode(StoredCredential.self, from: data)
                return credential.profileID == profileID ? id : nil
            }
            for id in matchingIDs {
                inMemoryItems!.removeValue(forKey: id)
            }
            return
        }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service(for: profileID)
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private func service(for profileID: UUID) -> String {
        "\(servicePrefix).\(profileID.uuidString.lowercased())"
    }

    func replace(profileID: UUID, with values: [StoredCredential]) throws {
        let existing = try credentials(profileID: profileID)
        let retained = Set(values.map(\.id))
        var errors: [String] = []
        for value in values {
            do { try save(value) } catch { errors.append(error.localizedDescription) }
        }
        for value in existing where !retained.contains(value.id) {
            do { try delete(value) } catch { errors.append(error.localizedDescription) }
        }
        if !errors.isEmpty { throw StorageTransactionError.recovery(errors.joined(separator: "\n")) }
    }
}

enum KeychainError: LocalizedError {
    case status(OSStatus)
    case invalidData

    init(status: OSStatus) {
        self = .status(status)
    }

    var errorDescription: String? {
        switch self {
        case .status(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "未知错误"
            return "钥匙串操作失败：\(message)（\(status)）"
        case .invalidData:
            return "钥匙串返回了无法识别的数据。"
        }
    }
}
