import Foundation
import Network

struct SocksProxyProbeResult: Sendable, Hashable {
    let status: SocksProxyStatus
    let latencyMilliseconds: Int?
    let message: String?

    init(
        status: SocksProxyStatus,
        latencyMilliseconds: Int? = nil,
        message: String? = nil
    ) {
        self.status = status
        self.latencyMilliseconds = latencyMilliseconds
        self.message = message
    }
}

/// A probe can be replaced in tests or by a caller that wants a custom
/// validation target. Implementations should throw for transport failures.
protocol SocksProxyProbe: Sendable {
    func probe(_ proxy: SocksProxy, timeout: TimeInterval) async throws -> SocksProxyProbeResult
}

struct SocksProxyValidationResult: Sendable, Hashable {
    let proxyID: UUID
    let status: SocksProxyStatus
    let latencyMilliseconds: Int?
    let checkedAt: Date
    let message: String?
}

struct SocksProxyValidationConfiguration: Sendable, Hashable {
    var timeout: TimeInterval
    /// When non-nil, the probe performs a SOCKS CONNECT request after the
    /// greeting/authentication handshake. Leaving it nil avoids a dependency
    /// on any third-party test endpoint while still verifying the SOCKS5
    /// server handshake.
    var targetHost: String?
    var targetPort: Int

    init(
        timeout: TimeInterval = 8,
        targetHost: String? = nil,
        targetPort: Int = 80
    ) {
        self.timeout = max(0.1, timeout)
        self.targetHost = targetHost
        self.targetPort = min(65_535, max(1, targetPort))
    }
}

struct SocksProxyValidationService: @unchecked Sendable {
    private let probe: any SocksProxyProbe
    private let timeout: TimeInterval

    init(
        configuration: SocksProxyValidationConfiguration = .init(),
        probe: (any SocksProxyProbe)? = nil
    ) {
        self.timeout = configuration.timeout
        self.probe = probe ?? NetworkSocksProxyProbe(configuration: configuration)
    }

    init(timeout: TimeInterval = 8, probe: any SocksProxyProbe) {
        self.timeout = max(0.1, timeout)
        self.probe = probe
    }

    func validate(_ proxy: SocksProxy) async -> SocksProxyValidationResult {
        let startedAt = Date()
        do {
            let result = try await probe.probe(proxy, timeout: timeout)
            let elapsed = max(1, Int(Date().timeIntervalSince(startedAt) * 1_000))
            return SocksProxyValidationResult(
                proxyID: proxy.id,
                status: result.status,
                latencyMilliseconds: result.latencyMilliseconds ?? elapsed,
                checkedAt: .now,
                message: result.message
            )
        } catch {
            let elapsed = max(1, Int(Date().timeIntervalSince(startedAt) * 1_000))
            return SocksProxyValidationResult(
                proxyID: proxy.id,
                status: .unavailable,
                latencyMilliseconds: elapsed,
                checkedAt: .now,
                message: error.localizedDescription
            )
        }
    }

    /// Validates in parallel using at most `maxConcurrent` workers. Results
    /// retain the input order; use `validateAndSort` when a ranked list is
    /// needed after the check.
    func validate(
        _ proxies: [SocksProxy],
        maxConcurrent: Int = 8
    ) async -> [SocksProxyValidationResult] {
        guard !proxies.isEmpty else { return [] }

        let workerCount = min(max(1, maxConcurrent), proxies.count)
        var buckets = Array(repeating: [(Int, SocksProxy)](), count: workerCount)
        for (index, proxy) in proxies.enumerated() {
            buckets[index % workerCount].append((index, proxy))
        }

        return await withTaskGroup(of: [(Int, SocksProxyValidationResult)].self) { group in
            for bucket in buckets {
                group.addTask {
                    var values: [(Int, SocksProxyValidationResult)] = []
                    values.reserveCapacity(bucket.count)
                    for (index, proxy) in bucket {
                        values.append((index, await validate(proxy)))
                    }
                    return values
                }
            }

            var collected: [(Int, SocksProxyValidationResult)] = []
            collected.reserveCapacity(proxies.count)
            for await values in group {
                collected.append(contentsOf: values)
            }
            return collected
                .sorted { $0.0 < $1.0 }
                .map(\.1)
        }
    }

    func validateAndSort(
        _ proxies: [SocksProxy],
        maxConcurrent: Int = 8
    ) async -> [SocksProxy] {
        let results = await validate(proxies, maxConcurrent: maxConcurrent)
        let resultByID = Dictionary(uniqueKeysWithValues: results.map { ($0.proxyID, $0) })
        let updated = proxies.map { proxy in
            guard let result = resultByID[proxy.id] else { return proxy }
            return proxy.applying(result)
        }
        return Self.sort(updated)
    }

    /// Sorts available records by latency and places untested/unavailable
    /// records after them. Swift's sort is not stable, so the original index
    /// is used as a final tie-breaker to prevent jitter between equal results.
    static func sort(_ proxies: [SocksProxy]) -> [SocksProxy] {
        proxies.enumerated().sorted { lhs, rhs in
            let leftRank = statusRank(lhs.element.status)
            let rightRank = statusRank(rhs.element.status)
            if leftRank != rightRank { return leftRank < rightRank }

            switch (lhs.element.latencyMilliseconds, rhs.element.latencyMilliseconds) {
            case let (left?, right?) where left != right:
                return left < right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    static func ranked(_ proxies: [SocksProxy]) -> [SocksProxyRanking] {
        sort(proxies).enumerated().map { index, proxy in
            SocksProxyRanking(number: index + 1, proxy: proxy)
        }
    }

    static func proxy(forDisplayNumber number: Int, in proxies: [SocksProxy]) -> SocksProxy? {
        guard number > 0 else { return nil }
        return ranked(proxies).first(where: { $0.number == number })?.proxy
    }

    private static func statusRank(_ status: SocksProxyStatus) -> Int {
        switch status {
        case .available: return 0
        case .untested: return 1
        case .unavailable: return 2
        }
    }
}

struct SocksProxyRanking: Identifiable, Sendable, Hashable {
    let number: Int
    let proxy: SocksProxy

    var id: UUID { proxy.id }
}

enum SocksProxyValidationError: LocalizedError, Equatable, Sendable {
    case timeout
    case connectionFailed
    case connectionCancelled
    case invalidHandshake
    case authenticationRequired
    case authenticationFailed
    case targetConnectionFailed
    case unsupportedAddress

    var errorDescription: String? {
        switch self {
        case .timeout:
            return "连接代理超时。"
        case .connectionFailed:
            return "无法连接代理服务器。"
        case .connectionCancelled:
            return "代理连接已取消。"
        case .invalidHandshake:
            return "代理返回了无效的 SOCKS5 握手。"
        case .authenticationRequired:
            return "代理需要账号密码，但当前记录未填写。"
        case .authenticationFailed:
            return "代理账号或密码验证失败。"
        case .targetConnectionFailed:
            return "代理无法连接测试目标。"
        case .unsupportedAddress:
            return "测试目标地址过长，无法通过 SOCKS5 发送。"
        }
    }
}

struct NetworkSocksProxyProbe: SocksProxyProbe {
    let configuration: SocksProxyValidationConfiguration

    init(configuration: SocksProxyValidationConfiguration = .init()) {
        self.configuration = configuration
    }

    func probe(_ proxy: SocksProxy, timeout: TimeInterval) async throws -> SocksProxyProbeResult {
        guard (1...65_535).contains(proxy.port),
              let port = NWEndpoint.Port(rawValue: UInt16(proxy.port)) else {
            throw SocksProxyValidationError.connectionFailed
        }
        let connection = NWConnection(
            host: NWEndpoint.Host(proxy.host),
            port: port,
            using: NWParameters.tcp
        )
        defer { connection.cancel() }

        try await Self.waitUntilReady(connection, timeout: timeout)
        let startedAt = Date()

        var methods: [UInt8] = [0x00]
        if proxy.username != nil || proxy.password != nil { methods.append(0x02) }
        guard methods.count <= 255 else { throw SocksProxyValidationError.invalidHandshake }
        try await Self.send(Data([0x05, UInt8(methods.count)] + methods), on: connection, timeout: timeout)

        let greeting = try await Self.receiveExact(2, from: connection, timeout: timeout)
        guard greeting[0] == 0x05 else { throw SocksProxyValidationError.invalidHandshake }
        switch greeting[1] {
        case 0x00:
            break
        case 0x02:
            guard let username = proxy.username,
                  let password = proxy.password else {
                throw SocksProxyValidationError.authenticationRequired
            }
            let usernameData = Data(username.utf8)
            let passwordData = Data(password.utf8)
            guard usernameData.count <= 255, passwordData.count <= 255 else {
                throw SocksProxyValidationError.authenticationFailed
            }
            var auth = Data([0x01, UInt8(usernameData.count)])
            auth.append(usernameData)
            auth.append(UInt8(passwordData.count))
            auth.append(passwordData)
            try await Self.send(auth, on: connection, timeout: timeout)
            let response = try await Self.receiveExact(2, from: connection, timeout: timeout)
            guard response[0] == 0x01, response[1] == 0x00 else {
                throw SocksProxyValidationError.authenticationFailed
            }
        case 0xFF:
            throw SocksProxyValidationError.authenticationFailed
        default:
            throw SocksProxyValidationError.invalidHandshake
        }

        if let targetHost = configuration.targetHost {
            try await Self.connectToTarget(
                host: targetHost,
                port: configuration.targetPort,
                on: connection,
                timeout: timeout
            )
        }

        let latency = max(1, Int(Date().timeIntervalSince(startedAt) * 1_000))
        return SocksProxyProbeResult(status: .available, latencyMilliseconds: latency)
    }

    private static func connectToTarget(
        host: String,
        port: Int,
        on connection: NWConnection,
        timeout: TimeInterval
    ) async throws {
        let hostData = Data(host.utf8)
        guard !hostData.isEmpty, hostData.count <= 255,
              (1...65_535).contains(port) else {
            throw SocksProxyValidationError.unsupportedAddress
        }

        var request = Data([0x05, 0x01, 0x00, 0x03, UInt8(hostData.count)])
        request.append(hostData)
        request.append(UInt8((port >> 8) & 0xff))
        request.append(UInt8(port & 0xff))
        try await send(request, on: connection, timeout: timeout)

        let header = try await receiveExact(4, from: connection, timeout: timeout)
        guard header[0] == 0x05 else { throw SocksProxyValidationError.invalidHandshake }
        guard header[1] == 0x00 else { throw SocksProxyValidationError.targetConnectionFailed }

        let addressLength: Int
        switch header[3] {
        case 0x01:
            addressLength = 4
        case 0x03:
            let lengthData = try await receiveExact(1, from: connection, timeout: timeout)
            addressLength = Int(lengthData[0])
        case 0x04:
            addressLength = 16
        default:
            throw SocksProxyValidationError.invalidHandshake
        }
        _ = try await receiveExact(addressLength + 2, from: connection, timeout: timeout)
    }

    private static func waitUntilReady(
        _ connection: NWConnection,
        timeout: TimeInterval
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = ContinuationGate()

            func finish(_ result: Result<Void, Error>) {
                gate.resume {
                    connection.stateUpdateHandler = nil
                    if case .failure = result {
                        connection.cancel()
                    }
                    continuation.resume(with: result)
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(.success(()))
                case .failed:
                    finish(.failure(SocksProxyValidationError.connectionFailed))
                case .cancelled:
                    finish(.failure(SocksProxyValidationError.connectionCancelled))
                default:
                    break
                }
            }
            connection.start(queue: DispatchQueue.global(qos: .utility))
            DispatchQueue.global(qos: .utility).asyncAfter(
                deadline: .now() + timeout
            ) {
                finish(.failure(SocksProxyValidationError.timeout))
            }
        }
    }

    private static func send(
        _ data: Data,
        on connection: NWConnection,
        timeout: TimeInterval
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = ContinuationGate()
            connection.send(content: data, completion: .contentProcessed { error in
                gate.resume {
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            })
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                gate.resume {
                    connection.cancel()
                    continuation.resume(throwing: SocksProxyValidationError.timeout)
                }
            }
        }
    }

    private static func receiveExact(
        _ count: Int,
        from connection: NWConnection,
        timeout: TimeInterval
    ) async throws -> Data {
        guard count > 0 else { return Data() }
        var result = Data()
        result.reserveCapacity(count)

        while result.count < count {
            let remaining = count - result.count
            let chunk = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                let gate = ContinuationGate()
                connection.receive(
                    minimumIncompleteLength: 1,
                    maximumLength: remaining
                ) { content, _, isComplete, error in
                    gate.resume {
                        if let error {
                            continuation.resume(throwing: error)
                        } else if let content, !content.isEmpty {
                            continuation.resume(returning: content)
                        } else if isComplete {
                            continuation.resume(throwing: SocksProxyValidationError.connectionFailed)
                        } else {
                            continuation.resume(throwing: SocksProxyValidationError.invalidHandshake)
                        }
                    }
                }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                    gate.resume {
                        connection.cancel()
                        continuation.resume(throwing: SocksProxyValidationError.timeout)
                    }
                }
            }
            result.append(chunk)
        }
        return result
    }
}

private final class ContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resume(_ action: () -> Void) {
        lock.lock()
        guard !didResume else {
            lock.unlock()
            return
        }
        didResume = true
        lock.unlock()
        action()
    }
}
