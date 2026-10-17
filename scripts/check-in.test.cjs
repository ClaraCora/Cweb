// Run with: node --test scripts/check-in.test.cjs
// Execute the actual bundled Swift string in a local, network-free DOM/timer
// harness. No browser clicks, real website requests, or third-party packages.
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { createHash } = require("node:crypto");
const { runInNewContext } = require("node:vm");
const assert = require("node:assert/strict");
const test = require("node:test");

const root = join(__dirname, "..");
const modelSource = readFileSync(join(root, "ProfileBrowser/Models/GlobalScriptSettings.swift"), "utf8");
function swiftString(source, marker) {
    const start = source.indexOf(marker);
    assert.notEqual(start, -1);
    const match = source.slice(start + marker.length).match(/^\r?\n([\s\S]*?)\r?\n( *)"""/);
    assert.ok(match, "Expected a Swift multiline string");
    const indent = match[2];
    const text = match[1].replace(/\r\n/g, "\n").split("\n").map(line => {
        assert.ok(!line.trim() || line.startsWith(indent));
        return line.slice(indent.length);
    }).join("\n");
    return text.replace(/\\(.)/g, (_, escape) => {
        const escapes = { "\\": "\\", '"': '"', n: "\n", r: "\r", t: "\t" };
        assert.ok(Object.hasOwn(escapes, escape), "Unsupported Swift escape: " + escape);
        return escapes[escape];
    });
}
const script = swiftString(modelSource, 'source: """');

function element(text, options = {}) {
    return {
        tag: options.tag || "button",
        textContent: text,
        disabled: false,
        attributes: {},
        laidOut: true,
        visibility: "visible",
        heading: false,
        clicks: 0,
        ...options,
        getClientRects() { return this.laidOut ? [{}] : []; },
        getAttribute(name) { return this.attributes[name] ?? null; },
        querySelector(selector) {
            assert.equal(selector, "h1, h2, h3, h4, h5, h6");
            return this.heading ? {} : null;
        },
        click() {
            this.clicks++;
            this.onClick?.();
        }
    };
}

// Small generic selector subset needed by the document under test. Unknown
// selectors fail loudly instead of silently making the tests pass.
function matches(node, selector) {
    if (/^[a-z]+$/.test(selector)) return node.tag === selector;
    if (selector.startsWith(".")) {
        return (node.attributes.class || "").split(/\s+/).includes(selector.slice(1));
    }
    const match = selector.match(/^([a-z]+)?\[([\w-]+)(?:(\*?=)"([^"]*)"( i)?)?\]$/);
    assert.ok(match, "Unsupported fixture selector: " + selector);
    const [, tag, key, operator, expected, insensitive] = match;
    if (tag && node.tag !== tag) return false;
    let value = node.attributes[key];
    if (value === undefined) return false;
    if (!operator) return true;
    let comparison = expected;
    if (insensitive) {
        value = value.toLowerCase();
        comparison = comparison.toLowerCase();
    }
    return operator === "*=" ? value.includes(comparison) : value === comparison;
}

function page(nodes = [], options = {}) {
    let now = 0;
    let nextTimer = 1;
    let paused = options.paused || false;
    const timers = new Map();
    const observers = [];
    const listeners = new Map();
    const events = [];
    const select = selector => nodes.filter(node =>
        selector.split(",").some(part => matches(node, part.trim())));
    const document = { documentElement: {}, querySelectorAll: select };
    const window = {
        getComputedStyle: node => ({ visibility: node.visibility }),
        addEventListener: (type, listener) => listeners.set(type, listener),
        CwebCheckIn: {
            isPaused: () => paused,
            success: message => events.push({ type: "success", message }),
            noButton: message => events.push({ type: "noButton", message }),
            captchaDetected: message => {
                paused = true;
                events.push({ type: "captcha", message });
            }
        }
    };
    const setTimeout = (callback, delay) => {
        const id = nextTimer++;
        timers.set(id, { at: now + delay, callback });
        return id;
    };
    const clearTimeout = id => timers.delete(id);
    class MutationObserver {
        constructor(callback) { this.callback = callback; observers.push(this); }
        observe() { this.connected = true; }
        disconnect() { this.connected = false; }
    }
    runInNewContext(script, { document, window, setTimeout, clearTimeout, MutationObserver }, { timeout: 1000 });
    return {
        events,
        types: () => events.map(event => event.type),
        advance(milliseconds) {
            const end = now + milliseconds;
            let iterations = 0;
            while (true) {
                const next = [...timers].sort((a, b) => a[1].at - b[1].at)[0];
                if (!next || next[1].at > end) break;
                assert.ok(++iterations < 1000, "Timer loop");
                const [id, timer] = next;
                now = timer.at;
                timers.delete(id);
                timer.callback();
            }
            now = end;
        },
        mutate(change) {
            change?.();
            observers.filter(observer => observer.connected).forEach(observer => observer.callback([]));
        },
        resume() {
            paused = false;
            listeners.get("cwebAutomationResume")?.();
        },
        recheck() {
            listeners.get("cwebAutomationRecheck")?.();
        }
    };
}

test("SuperAPI already checked in: no clicks, one success, no late error", () => {
    const header = element("每日签到\n已签到\n\n今天 +$0.1", { heading: true });
    const button = element("已签到", { disabled: true, attributes: { "data-disabled": "", "data-slot": "button" } });
    const p = page([header, button]);
    assert.deepEqual(p.types(), ["success"]);
    p.advance(7000);
    p.mutate(() => { button.textContent = "立即签到"; button.disabled = false; });
    p.resume();
    p.advance(7000);
    assert.equal(header.clicks + button.clicks, 0);
    assert.deepEqual(p.types(), ["success"]);
});

test("late-rendered completed state cancels the no-button timer", () => {
    const nodes = [];
    const p = page(nodes);
    p.advance(1000);
    p.mutate(() => nodes.push(element("已签到", { disabled: true })));
    p.advance(7000);
    assert.deepEqual(p.types(), ["success"]);
});

test("click the action once, skip the section heading, wait for actual completion", () => {
    const header = element("每日签到", { heading: true });
    const action = element("立即签到");
    const p = page([header, action]);
    assert.equal(header.clicks, 0);
    assert.equal(action.clicks, 1);
    p.advance(2000);
    assert.deepEqual(p.types(), []);
    p.mutate(() => { action.textContent = "已签到"; action.disabled = true; });
    p.advance(7000);
    p.mutate();
    p.advance(1000);
    assert.equal(action.clicks, 1);
    assert.deepEqual(p.types(), ["success"]);
});

test("unrelated success and hidden check-in labels cannot complete the day", () => {
    const p = page([
        element("保存成功 success 已完成", { tag: "div", attributes: { role: "status" } }),
        element("已签到", { laidOut: false }),
        element("签到成功", { visibility: "hidden" })
    ]);
    p.advance(7000);
    assert.deepEqual(p.types(), ["noButton"]);
});

test("disabled and invisible actions are not clicked", () => {
    const nodes = [
        element("立即签到", { disabled: true }),
        element("立即签到", { attributes: { "aria-disabled": "true" } }),
        element("立即签到", { laidOut: false })
    ];
    const p = page(nodes);
    p.advance(7000);
    assert.deepEqual(nodes.map(node => node.clicks), [0, 0, 0]);
    assert.deepEqual(p.types(), ["noButton"]);
});

test("visible CAPTCHA takes priority even alongside a completion label", () => {
    const nodes = [
        element("已签到", { disabled: true }),
        element("", { tag: "div", attributes: { class: "captcha" } })
    ];
    const p = page(nodes);
    p.advance(7000);
    p.mutate();
    p.advance(1000);
    assert.deepEqual(p.types(), ["captcha"]);
    p.mutate(() => nodes.pop());
    p.advance(1000);
    assert.deepEqual(p.types(), ["captcha"]);
    p.resume();
    p.advance(7000);
    assert.deepEqual(p.types(), ["captcha", "success"]);
});

test("CAPTCHA after clicking also pauses the delayed success check", () => {
    const action = element("立即签到");
    const nodes = [action];
    const p = page(nodes);
    p.mutate(() => {
        action.textContent = "已签到";
        nodes.push(element("", { tag: "iframe", attributes: { src: "https://example.invalid/captcha" } }));
    });
    p.advance(7000);
    assert.deepEqual(p.types(), ["captcha"]);
    assert.equal(action.clicks, 1);
});

test("a persisted pause prevents all activity until explicit resume", () => {
    const action = element("立即签到");
    const p = page([action], { paused: true });
    p.advance(7000);
    assert.equal(action.clicks, 0);
    assert.deepEqual(p.types(), []);
    p.mutate(() => { action.textContent = "已签到"; });
    p.resume();
    p.advance(7000);
    assert.deepEqual(p.types(), ["success"]);
    assert.equal(action.clicks, 0);
});

test("hidden CAPTCHA markup does not block a confirmed completed state", () => {
    const p = page([
        element("已签到", { disabled: true }),
        element("", { tag: "div", attributes: { class: "captcha" }, laidOut: false })
    ]);
    p.advance(7000);
    assert.deepEqual(p.types(), ["success"]);
});

test("explicit English check-in status is recognized", () => {
    const p = page([element("Already checked in", { disabled: true })]);
    p.advance(7000);
    assert.deepEqual(p.types(), ["success"]);
});

test("old saved template fingerprint matches the migration, current and edited copies do not", () => {
    const tests = readFileSync(join(root, "ProfileBrowserTests/AutomationScriptTests.swift"), "utf8");
    const legacy = swiftString(tests, 'originalBundledSource = """');
    const hash = source => createHash("sha256").update(source.trim()).digest("hex");
    const previous = swiftString(tests, 'previousBundledSource = """');
    const migrationHashes = [...modelSource.matchAll(/"([a-f0-9]{64})"/g)].map(match => match[1]);
    assert.ok(migrationHashes.includes(hash(legacy)));
    assert.ok(migrationHashes.includes(hash(previous)));
    assert.ok(!migrationHashes.includes(hash(script)));
    assert.ok(!migrationHashes.includes(hash(previous + "\n// Custom edit")));
});

test("plain visible page text can confirm today's check-in", () => {
    for (const text of ["已完成签到", "今天已完成签到", "今日签到：已完成"]) {
        const p = page([element(text, { tag: "p" })]);
        assert.deepEqual(p.types(), ["success"]);
    }
});

test("hidden and negative plain text never confirms completion", () => {
    const p = page([
        element("今天已完成签到", { tag: "span", laidOut: false }),
        element("已完成签到", { tag: "div", innerText: "" }),
        element("签到失败，未完成签到", { tag: "p" }),
        element("尚未签到", { tag: "div" })
    ]);
    p.advance(7000);
    assert.deepEqual(p.types(), ["noButton"]);
});

test("periodic recheck waits for a result without submitting twice", () => {
    const action = element("签到");
    const p = page([action]);
    for (let i = 0; i < 4; i++) {
        p.advance(5000);
        p.recheck();
        p.advance(250);
    }
    assert.equal(action.clicks, 1);
    assert.deepEqual(p.types(), []);
    action.textContent = "今天已完成签到";
    p.recheck();
    p.advance(250);
    assert.deepEqual(p.types(), ["success"]);
});

test("no-entry retries rearm reporting and find a later entry", () => {
    const nodes = [];
    const p = page(nodes);
    p.advance(6000);
    assert.deepEqual(p.types(), ["noButton"]);
    p.resume();
    p.advance(6000);
    assert.deepEqual(p.types(), ["noButton", "noButton"]);
    const action = element("立即签到");
    nodes.push(action);
    p.resume();
    p.advance(250);
    assert.equal(action.clicks, 1);
    assert.ok(!p.types().includes("success"));
});

test("an entry rendered after the no-entry report is never submitted twice by rechecks", () => {
    const nodes = [];
    const p = page(nodes);
    p.advance(6000);
    assert.deepEqual(p.types(), ["noButton"]);
    const action = element("立即签到");
    p.mutate(() => nodes.push(action));
    p.advance(250);
    for (let i = 0; i < 3; i++) {
        p.advance(5000);
        p.recheck();
        p.advance(250);
    }
    assert.equal(action.clicks, 1);
    assert.ok(!p.types().includes("success"));
});

test("retrying a CAPTCHA never clicks until it has disappeared", () => {
    const captcha = element("验证码", { tag: "div", attributes: { class: "captcha" } });
    const action = element("立即签到");
    const p = page([captcha, action]);
    for (let i = 0; i < 3; i++) {
        p.advance(5000);
        p.resume();
        p.advance(250);
    }
    assert.equal(action.clicks, 0);
    assert.ok(p.types().every(type => type === "captcha"));
    captcha.laidOut = false;
    p.resume();
    p.advance(250);
    assert.equal(action.clicks, 1);
    assert.ok(!p.types().includes("success"));
});

function bridgePage({ completed = false, paused = false, nativePaused = false, matches = ["*://*/*"], code = "" } = {}) {
    const source = readFileSync(join(root, "ProfileBrowser/Services/AutomationScriptBridge.swift"), "utf8");
    const raw = source.replaceAll('\\(matchJSON)', JSON.stringify(matches))
        .replaceAll('\\(completionKeyJSON)', '"daily"')
        .replaceAll('\\(AutomationBridge.messageName)', 'cwebAutomation')
        .replaceAll('\\(code)', code);
    const built = swiftString(raw, 'return """');
    const storage = new Map();
    if (completed) storage.set("daily", "1");
    if (paused) storage.set("daily.paused", "1");
    const events = [];
    const dispatched = [];
    const window = {
        __cwebAutomationManuallyPaused: nativePaused,
        location: { href: "https://example.com/checkin" },
        localStorage: {
            getItem: key => storage.get(key) ?? null,
            setItem: (key, value) => storage.set(key, value),
            removeItem: key => storage.delete(key)
        },
        webkit: { messageHandlers: { cwebAutomation: { postMessage: message => events.push(message) } } },
        dispatchEvent: event => dispatched.push(event.type)
    };
    class Event { constructor(type) { this.type = type; } }
    runInNewContext(built, { window, Event }, { timeout: 1000 });
    return { window, events, dispatched, storage, types: () => events.map(event => event.type) };
}

test("restored daily website record reports success to native without running script", () => {
    const p = bridgePage({ completed: true, code: "throw new Error('must not execute')" });
    assert.deepEqual(p.types(), ["success"]);
});

test("daily completion obeys the script's site match", () => {
    const p = bridgePage({ completed: true, matches: ["https://another.example/*"] });
    assert.deepEqual(p.types(), []);
});

test("manual pause persists and blocks success; resume restores completion once", () => {
    const p = bridgePage();
    const api = p.window.CwebCheckIn;
    api.pause();
    assert.equal(p.storage.get("daily.paused"), "1");
    api.success("must be blocked");
    assert.deepEqual(p.types(), []);
    api.resume();
    assert.equal(p.storage.has("daily.paused"), false);
    assert.deepEqual(p.dispatched, ["cwebAutomationResume"]);
    api.success("done");
    api.success("duplicate");
    assert.deepEqual(p.types(), ["resume", "success"]);
    api.pause();
    api.resume();
    assert.deepEqual(p.types(), ["resume", "success", "resume", "success"]);
});

test("persisted pause is visible to native and resumes for periodic retry", () => {
    const p = bridgePage({ paused: true });
    assert.deepEqual(p.types(), ["captcha"]);
    assert.equal(p.window.CwebCheckIn.isPaused(), true);
    p.window.CwebCheckIn.resume();
    assert.equal(p.window.CwebCheckIn.isPaused(), false);
    assert.deepEqual(p.types(), ["captcha", "resume"]);
});

test("native manual pause also applies on a new document with no website pause record", () => {
    const p = bridgePage({ nativePaused: true, code: "window.CwebCheckIn.success('must be blocked');" });
    assert.equal(p.window.CwebCheckIn.isPaused(), true);
    assert.deepEqual(p.types(), ["captcha"]);
});

test("completion found during native pause is delivered when the user resumes", () => {
    const p = bridgePage({ nativePaused: true, completed: true });
    assert.deepEqual(p.types(), []);
    p.window.CwebCheckIn.resume();
    assert.deepEqual(p.types(), ["resume", "success"]);
});
