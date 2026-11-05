enum BalanceReadScript {
    static let source = """
    if (document.readyState !== 'complete') return null;
    const visible = (node) => node && !node.closest('[hidden],[aria-hidden="true"]')
        && getComputedStyle(node).display !== 'none' && node.getClientRects().length > 0;
    if ([...document.querySelectorAll('[aria-busy="true"],[data-loading="true"],[role="progressbar"]')].some(visible)) return null;
    if (readySelector && !visible(document.querySelector(readySelector))) return null;
    let nodes;
    if (balanceSelector) nodes = [...document.querySelectorAll(balanceSelector)].filter(visible);
    else {
        nodes = [...document.querySelectorAll('[data-account-balance],[data-testid="account-balance"],[aria-label="账户余额"],[aria-label="Account balance"]')].filter(visible);
        if (!nodes.length) {
            // Compatibility fallback for the existing site, accepted only when unambiguous.
            nodes = [...document.querySelectorAll('div.text-foreground.font-mono.text-lg.font-bold.tracking-tight.tabular-nums')]
                .filter((node) => visible(node) && node.classList.contains('mt-1.5'));
        }
    }
    if (nodes.length !== 1) return null;
    const node = nodes[0];
    if (node.closest('[aria-busy="true"],[data-loading="true"]')) return null;
    const value = node.textContent?.trim();
    if (!value || value.length > 64 || !/[0-9]/.test(value) || /loading|加载|--/i.test(value)) return null;
    return value;
    """
}
