import Foundation

enum BrowserDocumentScript {
    static let identity = """
    (() => {
        window.__cwebDocumentID = window.crypto?.randomUUID?.() || String(Date.now()) + Math.random();
    })();
    """

    static func observer(runToken: String, rules: [WebsiteRule]) -> String {
        let token = String(data: try! JSONEncoder().encode(runToken), encoding: .utf8)!
        let rulesJSON = String(data: (try? JSONEncoder().encode(rules)) ?? Data("[]".utf8), encoding: .utf8)!
        return """
        (() => {
            const normalizeHost = value => String(value || '').trim().toLowerCase().replace(/\\.+$/, '');
            const siteHost = value => {
                const host = normalizeHost(value);
                const labels = host.split('.').filter(Boolean);
                if (labels.length < 2) return host;
                const suffix = labels.slice(-2).join('.');
                const commonTwoLabelSuffixes = new Set(['co.uk', 'org.uk', 'ac.uk', 'gov.uk', 'com.au', 'net.au', 'org.au', 'co.jp', 'com.cn', 'net.cn', 'org.cn']);
                return labels.slice(-(commonTwoLabelSuffixes.has(suffix) ? 3 : 2)).join('.');
            };
            const rule = (\(rulesJSON)).find(r => siteHost(r.host) === siteHost(location.hostname)) || {};
            const selector = rule.balanceSelector || '[data-account-balance],[data-testid="account-balance"],.dashboard-stat-value,.semi-statistic-content,.ant-statistic-content,div.font-mono.tabular-nums';
            let previous, timer;
            const state = n => {
                const style = getComputedStyle(n);
                return n.textContent + ':' + Boolean(n.closest('[aria-busy="true"],[data-loading="true"],[role="progressbar"],[hidden],[aria-hidden="true"]'))
                    + ':' + n.getClientRects().length + ':' + style.display + ':' + style.visibility;
            };
            const check = () => {
                let signature;
                try {
                    signature = location.href + '|' + [...document.querySelectorAll(selector)].slice(0,100)
                        .map(state).join('|');
                    if (rule.balanceReadySelector) signature += '|ready:' + [...document.querySelectorAll(rule.balanceReadySelector)].map(state).join('|');
                }
                catch (_) { return; }
                if (signature === previous) return;
                previous = signature;
                window.webkit?.messageHandlers?.cwebAutomation?.postMessage({
                    type: 'balanceChanged', runToken: \(token), documentID: window.__cwebDocumentID
                });
            };
            new MutationObserver(() => {
                if (timer) return;
                timer = setTimeout(() => { timer = undefined; check(); }, 400);
            })
                .observe(document.documentElement, {childList:true, subtree:true, characterData:true, attributes:true});
            check();
        })();
        """
    }
}
