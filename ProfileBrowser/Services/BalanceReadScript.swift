enum BalanceReadScript {
    static let source = """
    // Images and unrelated widgets can keep a usable document at interactive.
    if (document.readyState === 'loading') return null;
    const visible = (node) => {
        if (!node || node.closest('[hidden],[aria-hidden="true"]')) return false;
        const style = getComputedStyle(node);
        return style.display !== 'none' && style.visibility !== 'hidden'
            && style.visibility !== 'collapse' && node.getClientRects().length > 0;
    };
    if (readySelector && !visible(document.querySelector(readySelector))) return null;
    const isBalanceLabel = (text) => /^(?:(?:当前|當前|账户|帳戶|帐户|賬戶|可用|剩余|剩餘|钱包|錢包)?(?:余额|餘額)|剩余额度|剩餘額度|可用额度|可用額度|(?:(?:current|available|account|remaining|wallet)\\s+)?balance)(?:\\s*[（(](?:USD|CNY|RMB|EUR|美元|元)[）)])?\\s*[:：]?$/i.test((text || '').trim());
    let verified = true;
    let nodes;
    if (balanceSelector) nodes = [...document.querySelectorAll(balanceSelector)].filter(visible);
    else {
        nodes = [...document.querySelectorAll('[data-account-balance],[data-testid="account-balance"],[aria-label="账户余额"],[aria-label="Account balance"]')].filter(visible);
        if (!nodes.length) {
            // Match each label to the value inside its own statistic card.
            // JuAPI uses dashboard-stat-*; other dashboards use Semi/Ant cards.
            // Do not borrow numbers from adjacent consumption or request cards.
            let foundBalanceCard = false;
            for (const [container, labelSelector, valueSelector] of [
                ['.dashboard-stat-copy', '.dashboard-stat-label', '.dashboard-stat-value'],
                ['.semi-statistic', '.semi-statistic-title', '.semi-statistic-content'],
                ['.ant-statistic', '.ant-statistic-title', '.ant-statistic-content']
            ]) {
                for (const card of document.querySelectorAll(container)) {
                    if (!visible(card)) continue;
                    const labels = [...card.querySelectorAll(labelSelector)].filter(visible);
                    if (!labels.some((label) => isBalanceLabel(label.textContent))) continue;
                    foundBalanceCard = true;
                    nodes.push(...[...card.querySelectorAll(valueSelector)].filter(visible));
                }
            }
            // A balance card that is still loading must not fall back to a
            // different amount just because its value has not rendered yet.
            if (foundBalanceCard && !nodes.length) return null;
        }
        if (!nodes.length) {
            // These sites reuse the amount style for consumption and recharge
            // cards. Prefer a nearby balance label; preserve the original first
            // amount fallback when no labels exist (native marks it unverified).
            nodes = [...document.querySelectorAll('div.text-foreground.font-mono.text-lg.font-bold.tracking-tight.tabular-nums')]
                .filter((node) => visible(node) && node.classList.contains('mt-1.5'));
            const labeled = nodes.filter((node) => {
                let parent = node.parentElement;
                for (let depth = 0; parent && depth < 3; depth++, parent = parent.parentElement) {
                    // Never borrow a label from a neighboring amount card.
                    if (nodes.some((other) => other !== node && parent.contains(other))) break;
                    if ([...parent.querySelectorAll('*')].some((label) =>
                        label !== node && !label.contains(node) && visible(label)
                        && isBalanceLabel(label.textContent))) return true;
                }
                return false;
            });
            verified = labeled.length > 0;
            nodes = labeled.length ? labeled : nodes.slice(0, 1);
        }
    }
    if (!nodes.length) return null;
    const values = nodes.map((node) => {
        if (node.closest('[aria-busy="true"],[data-loading="true"],[role="progressbar"]')) return null;
        if ([...node.querySelectorAll('[aria-busy="true"],[data-loading="true"],[role="progressbar"]')].some(visible)) return null;
        const value = (node.innerText ?? node.textContent)?.trim();
        if (!value || value.length > 64 || !/[0-9]/.test(value) || /loading|加载|--/i.test(value)) return null;
        return value;
    });
    // Responsive copies with the same value are safe; conflicting explicit
    // sources or labeled balances remain unreadable rather than guessing.
    if (values.some((value) => value === null) || new Set(values).size !== 1) return null;
    return { value: values[0], verified };
    """
}
