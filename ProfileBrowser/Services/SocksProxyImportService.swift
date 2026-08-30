import Foundation

struct SocksProxyImportService: @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func parse(_ content: String, ignoringInvalid: Bool = true) throws -> [SocksProxy] {
        try SocksProxyParser.parseList(content, ignoringInvalid: ignoringInvalid)
    }

    /// Downloads a plain-text proxy feed over HTTP(S) and parses each line.
    /// The app only performs this request when the user explicitly invokes an
    /// import or preset refresh.
    func fetch(from url: URL, ignoringInvalid: Bool = true) async throws -> [SocksProxy] {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            throw SocksProxyImportError.invalidFeedURL
        }
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw SocksProxyImportError.invalidResponse
        }
        guard let content = String(data: data, encoding: .utf8) else {
            throw SocksProxyImportError.invalidEncoding
        }
        return try parse(content, ignoringInvalid: ignoringInvalid)
    }
}

enum SocksProxyImportError: LocalizedError, Equatable, Sendable {
    case invalidFeedURL
    case invalidResponse
    case invalidEncoding

    var errorDescription: String? {
        switch self {
        case .invalidFeedURL:
            return "代理订阅链接必须是 HTTP 或 HTTPS 地址。"
        case .invalidResponse:
            return "代理订阅链接返回了无效响应。"
        case .invalidEncoding:
            return "代理订阅内容不是有效的 UTF-8 文本。"
        }
    }
}
