import Foundation

struct WebOrigin: Codable, Hashable, Sendable {
    let scheme: String
    let host: String
    let port: Int

    init?(url: URL) {
        guard
            let scheme = url.scheme?.lowercased(),
            scheme == "https" || scheme == "http",
            let host = url.host(percentEncoded: false)?.lowercased(),
            !host.isEmpty
        else {
            return nil
        }

        self.scheme = scheme
        self.host = host
        self.port = url.port ?? (scheme == "https" ? 443 : 80)
    }

    var isSecure: Bool { scheme == "https" }

    var displayString: String {
        let defaultPort = scheme == "https" ? 443 : 80
        return port == defaultPort ? "\(scheme)://\(host)" : "\(scheme)://\(host):\(port)"
    }
}
