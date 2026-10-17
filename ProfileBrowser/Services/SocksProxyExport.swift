import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum SocksProxyExport {
    /// Keep export separate from displayAddress, which intentionally redacts
    /// passwords. Encode reserved characters so each line can be re-imported.
    static func text(for proxies: [SocksProxy]) throws -> String {
        try proxies.map { proxy in
            var components = URLComponents()
            components.scheme = proxy.scheme.rawValue
            let host = SocksProxy.normalizeHost(proxy.host)
            guard (1...65_535).contains(proxy.port), !host.isEmpty else {
                throw SocksProxyParseError.invalidValue
            }
            components.host = host.contains(":") ? "[\(host)]" : host
            components.port = proxy.port
            let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
            components.percentEncodedUser = proxy.username?.addingPercentEncoding(withAllowedCharacters: unreserved)
            components.percentEncodedPassword = proxy.password?.addingPercentEncoding(withAllowedCharacters: unreserved)
            guard let value = components.string,
                  let parsed = try? SocksProxy(urlString: value),
                  parsed.host == host,
                  parsed.username == proxy.username,
                  parsed.password == proxy.password else {
                throw SocksProxyParseError.invalidValue
            }
            return value
        }.joined(separator: "\n") + (proxies.isEmpty ? "" : "\n")
    }
}

struct SocksProxyExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String

    init(text: String = "") { self.text = text }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw SocksProxyImportError.invalidEncoding
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
