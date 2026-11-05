import Foundation

struct SocksProxyImportService: @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func parse(_ content: String, ignoringInvalid: Bool = true) throws -> [SocksProxy] {
        try SocksProxyParser.parseList(content, ignoringInvalid: ignoringInvalid)
    }

    static let maximumBytes = 2 * 1024 * 1024

    func fetchText(from url: URL) async throws -> String {
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { throw SocksProxyImportError.invalidFeedURL }
        let request = URLRequest(url: url, timeoutInterval: 30)
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw SocksProxyImportError.invalidResponse }
        guard response.expectedContentLength <= Int64(Self.maximumBytes) else { throw SocksProxyImportError.tooLarge }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < Self.maximumBytes else { throw SocksProxyImportError.tooLarge }
            data.append(byte)
        }
        guard let text = String(data: data, encoding: .utf8) else { throw SocksProxyImportError.invalidEncoding }
        return text
    }

    func fetch(from url: URL, ignoringInvalid: Bool = true) async throws -> [SocksProxy] {
        try parse(await fetchText(from: url), ignoringInvalid: ignoringInvalid)
    }

    static func parseDetailed(_ content: String) throws -> ProxyParseReport {
        guard content.utf8.count <= maximumBytes else { throw SocksProxyImportError.tooLarge }
        var result = ProxyParseReport()
        var indices: [String: Int] = [:]
        for (index, raw) in content.components(separatedBy: .newlines).enumerated() {
            var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("//") else { continue }
            if let comment = line.firstIndex(of: "#") { line = String(line[..<comment]) }
            for token in line.split(whereSeparator: { $0.isWhitespace || $0 == "," }) {
                do {
                    let value = try SocksProxy(urlString: String(token))
                    if let old = indices[value.identityKey] {
                        result.duplicates += 1
                        result.proxies[old] = value
                    } else {
                        indices[value.identityKey] = result.proxies.count
                        result.proxies.append(value)
                    }
                } catch {
                    result.invalid.append(ProxyImportIssue(line: index + 1, reason: error.localizedDescription))
                }
            }
        }
        return result
    }

    static func readTextFile(_ url: URL) throws -> String {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw SocksProxyImportError.invalidEncoding }
        guard let size = values.fileSize, size <= maximumBytes else { throw SocksProxyImportError.tooLarge }
        let data = try Data(contentsOf: url)
        guard data.count <= maximumBytes else { throw SocksProxyImportError.tooLarge }
        guard let text = String(data: data, encoding: .utf8) else { throw SocksProxyImportError.invalidEncoding }
        return text
    }

}

enum SocksProxyImportError: LocalizedError, Equatable, Sendable {
    case invalidFeedURL
    case invalidResponse
    case invalidEncoding
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .invalidFeedURL:
            return "代理订阅链接必须是 HTTP 或 HTTPS 地址。"
        case .invalidResponse:
            return "代理订阅链接返回了无效响应。"
        case .tooLarge: return "代理文本超过 2 MB 上限。"
        case .invalidEncoding:
            return "代理订阅内容不是有效的 UTF-8 文本。"
        }
    }
}

struct ProxyImportIssue: Identifiable, Sendable {
    var id = UUID()
    let line: Int
    let reason: String
}
struct ProxyParseReport: Sendable {
    var proxies: [SocksProxy] = []
    var duplicates = 0
    var invalid: [ProxyImportIssue] = []
}
struct ProxyImportReport: Identifiable {
    let id = UUID()
    var added = 0
    var updated = 0
    var duplicates = 0
    var invalid: [ProxyImportIssue] = []
    var summary: String { "新增 \(added) · 更新 \(updated) · 重复 \(duplicates) · 无效 \(invalid.count)" }
}
