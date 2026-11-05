import Foundation

enum StorageTransaction {
    static func perform(_ operation: () throws -> Void, rollback: () throws -> Void) throws {
        do { try operation() }
        catch {
            let original = error
            do { try rollback() }
            catch {
                throw StorageTransactionError.rollbackFailed(
                    operation: original.localizedDescription, recovery: error.localizedDescription
                )
            }
            throw original
        }
    }

    /// Attempt every recovery action; one damaged item must not prevent the
    /// remaining items from being restored.
    static func restoreAll<T>(_ values: [T], restore: (T) throws -> Void) throws {
        var errors: [String] = []
        for value in values {
            do { try restore(value) }
            catch { errors.append(error.localizedDescription) }
        }
        if !errors.isEmpty { throw StorageTransactionError.recovery(errors.joined(separator: "\n")) }
    }
}

enum StorageTransactionError: LocalizedError {
    case rollbackFailed(operation: String, recovery: String)
    case recovery(String)

    var errorDescription: String? {
        switch self {
        case let .rollbackFailed(operation, recovery):
            "保存失败且未能完整恢复原数据。请保留当前数据并重试恢复，避免重复提交。\n\n操作：\(operation)\n恢复：\(recovery)"
        case .recovery(let message): message
        }
    }
}
