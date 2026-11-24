import Foundation

struct ProxyBindingResolver {
    let rankings: [SocksProxyRanking]
    private let numberByID: [UUID: Int]

    init(rankings: [SocksProxyRanking]) {
        self.rankings = rankings
        // As in the original lookup, the first matching ID wins.
        numberByID = Dictionary(rankings.lazy.map { ($0.id, $0.number) }, uniquingKeysWith: { first, _ in first })
    }

    func number(forID id: UUID) -> Int? { numberByID[id] }

    func proxy(forNumber number: Int?) -> SocksProxy? {
        guard let number, number > 0, number <= rankings.count else { return nil }
        return rankings[number - 1].proxy
    }

    func resolve(_ profile: BrowserProfile) -> SocksProxy? {
        guard profile.unresolvedProxyNumber == nil else { return nil }
        if let id = profile.fixedProxyID { return proxy(forNumber: numberByID[id]) }
        return proxy(forNumber: profile.socksProxyNumber)
    }

    func number(_ profile: BrowserProfile) -> Int? {
        if let id = profile.fixedProxyID { return numberByID[id] ?? profile.socksProxyNumber }
        return profile.socksProxyNumber
    }
}
