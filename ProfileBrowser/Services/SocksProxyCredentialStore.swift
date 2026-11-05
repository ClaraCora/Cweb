import Foundation
import Security

/// Keeps proxy passwords out of the JSON files. The in-memory mode is used by
/// unit tests and is also useful for previews.
final class SocksProxyCredentialStore: @unchecked Sendable {
    private let service = "com.personal.profilebrowser.socks-proxy"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var inMemoryItems: [UUID: Data]?
    private let lock = NSLock()

    private let beforeMutation: (@Sendable (UUID) throws -> Void)?

    init(inMemory: Bool = false, beforeMutation: (@Sendable (UUID) throws -> Void)? = nil) {
        self.beforeMutation = beforeMutation
        inMemoryItems = inMemory ? [:] : nil
    }

    func password(for proxyID: UUID) throws -> String? {
        if isInMemory {
            guard let inMemoryData = inMemoryData(for: proxyID) else { return nil }
            return try decoder.decode(String.self, from: inMemoryData)
        }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: proxyID.uuidString,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError(status: status)
        }
        return try decoder.decode(String.self, from: data)
    }

    func save(password: String?, for proxyID: UUID) throws {
        try beforeMutation?(proxyID)
        let normalized = password?.isEmpty == false ? password : nil
        if inMemoryItems != nil {
            lock.lock()
            defer { lock.unlock() }
            if let normalized {
                inMemoryItems![proxyID] = try encoder.encode(normalized)
            } else {
                inMemoryItems!.removeValue(forKey: proxyID)
            }
            return
        }

        guard let normalized else {
            try delete(for: proxyID)
            return
        }
        let data = try encoder.encode(normalized)
        let identity: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: proxyID.uuidString
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

    func delete(for proxyID: UUID) throws {
        try beforeMutation?(proxyID)
        if inMemoryItems != nil {
            lock.lock()
            inMemoryItems!.removeValue(forKey: proxyID)
            lock.unlock()
            return
        }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: proxyID.uuidString
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    func deleteAll() throws {
        if inMemoryItems != nil {
            lock.lock()
            inMemoryItems!.removeAll()
            lock.unlock()
            return
        }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private func inMemoryData(for proxyID: UUID) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return inMemoryItems?[proxyID]
    }

    private var isInMemory: Bool {
        lock.lock()
        defer { lock.unlock() }
        return inMemoryItems != nil
    }
}
