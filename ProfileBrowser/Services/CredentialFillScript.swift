enum CredentialFillScript {
    static let source = """
    const visible = (input) => {
        if (!input || input.disabled || input.readOnly || input.type === 'hidden') return false;
        if (input.closest('[hidden], [inert], [aria-hidden="true"]')) return false;
        const style = getComputedStyle(input);
        return style.display !== 'none' && style.visibility !== 'hidden' && input.getClientRects().length > 0;
    };
    const passwords = [...document.querySelectorAll('input[type="password"]')]
        .filter((input) => visible(input) && input.autocomplete !== 'new-password');
    const active = document.activeElement;
    const passwordInput = passwords.find((input) => input === active || (input.form && input.form === active?.form))
        || passwords.find((input) => input.autocomplete === 'current-password') || passwords[0];
    if (!passwordInput) return { usernameFilled: false, passwordFilled: false };
    let scope = passwordInput.form || passwordInput.closest('[role="form"]');
    if (!scope) {
        let parent = passwordInput.parentElement;
        for (let depth = 0; parent && parent !== document.body && depth < 4; depth++, parent = parent.parentElement) {
            if (parent.querySelectorAll('input:not([type="password"])').length) { scope = parent; break; }
        }
    }
    const priorities = ['input[autocomplete="username"]', 'input[type="email"]',
        'input[name*="user" i]', 'input[name*="login" i]', 'input[type="text"]', 'input:not([type])'];
    let usernameInput = null;
    if (scope) {
        for (const selector of priorities) {
            usernameInput = [...scope.querySelectorAll(selector)].find((input) => visible(input)
                && input.type !== 'search' && input.type !== 'password'
                && !/search|query|captcha|verify|code/i.test(input.name || '')
                && (!passwordInput.form || input.form === passwordInput.form));
            if (usernameInput) break;
        }
    }
    const setValue = (element, value) => {
        if (!element) return false;
        Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(element, value);
        element.dispatchEvent(new Event('input', { bubbles: true }));
        element.dispatchEvent(new Event('change', { bubbles: true }));
        return true;
    };
    return { usernameFilled: setValue(usernameInput, username), passwordFilled: setValue(passwordInput, password) };
    """
}
