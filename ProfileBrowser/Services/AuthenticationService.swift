import LocalAuthentication

@MainActor
struct AuthenticationService {
    func authenticate(reason: String) async throws {
        let context = LAContext()
        context.localizedCancelTitle = "取消"

        var evaluationError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evaluationError) else {
            throw evaluationError ?? AuthenticationError.unavailable
        }

        let succeeded = try await context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: reason
        )
        guard succeeded else { throw AuthenticationError.failed }
    }
}

enum AuthenticationError: LocalizedError {
    case unavailable
    case failed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "这台设备未启用可用的身份验证方式。"
        case .failed:
            return "身份验证未通过。"
        }
    }
}
