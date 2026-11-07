import Foundation

enum ProxyBindingResolver {
    static func resolve(_ profile: BrowserProfile, rankings: [SocksProxyRanking]) -> SocksProxy? {
        guard profile.unresolvedProxyNumber == nil else { return nil }
        if let id = profile.fixedProxyID { return rankings.first { $0.id == id }?.proxy }
        return rankings.first { $0.number == profile.socksProxyNumber }?.proxy
    }

    static func number(_ profile: BrowserProfile, rankings: [SocksProxyRanking]) -> Int? {
        if let id = profile.fixedProxyID { return rankings.first { $0.id == id }?.number ?? profile.socksProxyNumber }
        return profile.socksProxyNumber
    }
}
