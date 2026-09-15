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
    const migrationHash = modelSource.match(/guard digest == "([a-f0-9]{64})"/)[1];
    assert.equal(hash(legacy), migrationHash);
    assert.notEqual(hash(script), migrationHash);
    assert.notEqual(hash(legacy + "\n// Custom edit"), migrationHash);
});
