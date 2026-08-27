<?php
declare(strict_types=1);

function h(?string $value): string
{
    return htmlspecialchars($value ?? '', ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function request_headers(): array
{
    if (function_exists('getallheaders')) {
        $headers = getallheaders();
        if (is_array($headers)) {
            return $headers;
        }
    }

    $headers = [];
    foreach ($_SERVER as $key => $value) {
        if (strpos($key, 'HTTP_') === 0) {
            $name = str_replace('_', '-', strtolower(substr($key, 5)));
            $headers[$name] = (string) $value;
        }
    }
    if (isset($_SERVER['CONTENT_TYPE'])) {
        $headers['content-type'] = (string) $_SERVER['CONTENT_TYPE'];
    }
    if (isset($_SERVER['CONTENT_LENGTH'])) {
        $headers['content-length'] = (string) $_SERVER['CONTENT_LENGTH'];
    }
    return $headers;
}

function is_sensitive_header(string $name): bool
{
    return in_array(strtolower($name), [
        'authorization',
        'proxy-authorization',
        'cookie',
        'set-cookie',
        'x-api-key',
    ], true);
}

$headers = request_headers();
uksort($headers, static fn (string $a, string $b): int => strcasecmp($a, $b));

$safeHeaders = [];
foreach ($headers as $name => $value) {
    $safeHeaders[$name] = is_sensitive_header($name) ? '[已隐藏]' : (string) $value;
}

$serverRows = [
    ['请求方法', $_SERVER['REQUEST_METHOD'] ?? '未知'],
    ['请求路径', $_SERVER['REQUEST_URI'] ?? '/'],
    ['客户端 IP', $_SERVER['REMOTE_ADDR'] ?? '未知'],
    ['协议', $_SERVER['SERVER_PROTOCOL'] ?? '未知'],
    ['HTTPS', (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? '已启用' : '未启用'],
    ['服务器软件', $_SERVER['SERVER_SOFTWARE'] ?? '未知'],
    ['PHP 版本', PHP_VERSION],
];

$serverUserAgent = $_SERVER['HTTP_USER_AGENT'] ?? '未知';
foreach ($headers as $headerName => $headerValue) {
    if (strcasecmp((string) $headerName, 'User-Agent') === 0) {
        $serverUserAgent = (string) $headerValue;
        break;
    }
}
$generatedAt = (new DateTimeImmutable('now'))->format(DateTimeInterface::ATOM);
?>
<!doctype html>
<html lang="zh-CN">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="color-scheme" content="light dark">
    <title>UA / 环境检测</title>
    <style>
        :root {
            color-scheme: light;
            --bg: #f3f6fa;
            --panel: #ffffff;
            --panel-muted: #f7fafc;
            --ink: #132235;
            --muted: #5f7185;
            --line: #dbe4ed;
            --accent: #007f7b;
            --accent-soft: #dff5f1;
            --warning: #8a5a00;
            --warning-soft: #fff5dc;
            --shadow: 0 12px 32px rgba(19, 34, 53, .08);
        }

        @media (prefers-color-scheme: dark) {
            :root {
                color-scheme: dark;
                --bg: #0b1420;
                --panel: #111e2d;
                --panel-muted: #0d1927;
                --ink: #edf5fc;
                --muted: #a8b8c8;
                --line: #26394c;
                --accent: #56d6ca;
                --accent-soft: #123a3a;
                --warning: #ffd277;
                --warning-soft: #3b2d10;
                --shadow: 0 14px 36px rgba(0, 0, 0, .2);
            }
        }

        * { box-sizing: border-box; }
        body {
            margin: 0;
            background: var(--bg);
            color: var(--ink);
            font: 15px/1.55 ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        }
        a { color: inherit; }
        .shell { width: min(1180px, calc(100% - 32px)); margin: 0 auto; padding: 42px 0 64px; }
        .header { display: flex; justify-content: space-between; gap: 24px; align-items: flex-start; margin-bottom: 28px; }
        .eyebrow { margin: 0 0 8px; color: var(--accent); font-size: 12px; font-weight: 750; letter-spacing: .08em; text-transform: uppercase; }
        h1, h2, p { margin-top: 0; }
        h1 { margin-bottom: 10px; font-size: clamp(28px, 4vw, 42px); line-height: 1.1; letter-spacing: 0; }
        .lede { max-width: 66ch; margin-bottom: 0; color: var(--muted); }
        .actions { display: flex; flex-wrap: wrap; justify-content: flex-end; gap: 10px; }
        button {
            min-height: 42px;
            border: 1px solid var(--line);
            border-radius: 9px;
            padding: 9px 14px;
            background: var(--panel);
            color: var(--ink);
            cursor: pointer;
            font: inherit;
            font-weight: 700;
        }
        button:hover { border-color: var(--accent); }
        button:focus-visible { outline: 3px solid color-mix(in srgb, var(--accent) 35%, transparent); outline-offset: 2px; }
        .primary { border-color: var(--accent); background: var(--accent); color: #fff; }
        .status { display: inline-flex; align-items: center; gap: 8px; min-height: 34px; padding: 6px 10px; border: 1px solid var(--line); border-radius: 999px; color: var(--muted); white-space: nowrap; }
        .status::before { width: 8px; height: 8px; border-radius: 50%; background: #21a366; content: ""; }
        .notice { display: flex; gap: 10px; align-items: flex-start; margin-bottom: 22px; padding: 13px 15px; border: 1px solid color-mix(in srgb, var(--warning) 28%, var(--line)); border-radius: 10px; background: var(--warning-soft); color: var(--warning); }
        .notice strong { color: var(--ink); }
        .grid { display: grid; grid-template-columns: repeat(12, minmax(0, 1fr)); gap: 18px; }
        .panel { grid-column: span 6; min-width: 0; border: 1px solid var(--line); border-radius: 12px; background: var(--panel); box-shadow: var(--shadow); overflow: hidden; }
        .panel.wide { grid-column: 1 / -1; }
        .panel-head { display: flex; justify-content: space-between; align-items: baseline; gap: 16px; padding: 19px 20px 14px; border-bottom: 1px solid var(--line); }
        h2 { margin-bottom: 0; font-size: 18px; line-height: 1.25; }
        .panel-caption { color: var(--muted); font-size: 13px; }
        .table-wrap { overflow-x: auto; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 11px 20px; border-bottom: 1px solid var(--line); text-align: left; vertical-align: top; }
        tr:last-child th, tr:last-child td { border-bottom: 0; }
        th { width: 31%; color: var(--muted); font-weight: 650; white-space: nowrap; }
        td { overflow-wrap: anywhere; font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size: 13px; }
        .ua { padding: 16px 20px 20px; }
        .ua-value { margin: 0; padding: 14px; border: 1px solid var(--line); border-radius: 8px; background: var(--panel-muted); overflow-wrap: anywhere; font: 13px/1.65 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
        .metrics { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 1px; background: var(--line); }
        .metric { min-width: 0; padding: 16px 18px; background: var(--panel); }
        .metric-label { display: block; margin-bottom: 4px; color: var(--muted); font-size: 12px; }
        .metric-value { display: block; overflow-wrap: anywhere; font-weight: 750; }
        .chips { display: flex; flex-wrap: wrap; gap: 8px; padding: 17px 20px 20px; }
        .chip { padding: 6px 9px; border: 1px solid var(--line); border-radius: 7px; background: var(--panel-muted); color: var(--muted); font: 12px ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
        .chip.ok { border-color: color-mix(in srgb, var(--accent) 35%, var(--line)); background: var(--accent-soft); color: var(--accent); }
        .footer { margin-top: 24px; color: var(--muted); font-size: 13px; }
        .toast { position: fixed; right: 18px; bottom: 18px; z-index: 2; transform: translateY(12px); opacity: 0; pointer-events: none; padding: 10px 13px; border-radius: 8px; background: var(--ink); color: var(--bg); transition: opacity .18s ease, transform .18s ease; }
        .toast.show { transform: translateY(0); opacity: 1; }
        @media (max-width: 760px) {
            .shell { width: min(100% - 22px, 680px); padding-top: 26px; }
            .header { display: block; }
            .actions { justify-content: flex-start; margin-top: 18px; }
            .panel { grid-column: 1 / -1; }
            .metrics { grid-template-columns: repeat(2, minmax(0, 1fr)); }
            th, td { padding-right: 14px; padding-left: 14px; }
            th { width: 38%; }
        }
        @media (prefers-reduced-motion: reduce) { .toast { transition: none; } }
    </style>
</head>
<body>
<main class="shell">
    <header class="header">
        <div>
            <p class="eyebrow">Cweb / diagnostics</p>
            <h1>UA / 环境检测</h1>
            <p class="lede">对比不同浏览器环境看到的 User-Agent、请求头、设备参数与浏览器能力。页面不会把浏览器端数据提交到服务器。</p>
        </div>
        <div class="actions">
            <span class="status">本次页面检测中</span>
            <button class="primary" id="copy-report" type="button">复制 JSON 报告</button>
        </div>
    </header>

    <div class="notice" role="note">
        <span aria-hidden="true">ⓘ</span>
        <div><strong>隐私提示：</strong>服务端只展示脱敏后的请求信息；Cookie、Authorization 等敏感请求头不会显示。IP 地址仍属于你的网站访问日志范围，请按自己的隐私政策处理。</div>
    </div>

    <section class="grid" aria-label="检测结果">
        <article class="panel wide">
            <div class="panel-head">
                <h2>服务端看到的 User-Agent</h2>
                <span class="panel-caption">PHP / HTTP 请求</span>
            </div>
            <div class="ua"><p class="ua-value"><?= h($serverUserAgent) ?></p></div>
        </article>

        <article class="panel">
            <div class="panel-head"><h2>请求与服务器</h2><span class="panel-caption">server-side</span></div>
            <div class="table-wrap"><table>
                <tbody>
                <?php foreach ($serverRows as [$label, $value]): ?>
                    <tr><th><?= h((string) $label) ?></th><td><?= h((string) $value) ?></td></tr>
                <?php endforeach; ?>
                </tbody>
            </table></div>
        </article>

        <article class="panel">
            <div class="panel-head"><h2>浏览器核心信息</h2><span class="panel-caption">client-side</span></div>
            <div class="metrics">
                <div class="metric"><span class="metric-label">navigator.userAgent</span><strong class="metric-value" id="client-ua">读取中…</strong></div>
                <div class="metric"><span class="metric-label">平台</span><strong class="metric-value" id="platform">读取中…</strong></div>
                <div class="metric"><span class="metric-label">语言</span><strong class="metric-value" id="language">读取中…</strong></div>
                <div class="metric"><span class="metric-label">时区</span><strong class="metric-value" id="timezone">读取中…</strong></div>
                <div class="metric"><span class="metric-label">在线状态</span><strong class="metric-value" id="online">读取中…</strong></div>
                <div class="metric"><span class="metric-label">自动化标记</span><strong class="metric-value" id="webdriver">读取中…</strong></div>
            </div>
        </article>

        <article class="panel">
            <div class="panel-head"><h2>视口与设备</h2><span class="panel-caption">实时读取</span></div>
            <div class="metrics">
                <div class="metric"><span class="metric-label">视口</span><strong class="metric-value" id="viewport">读取中…</strong></div>
                <div class="metric"><span class="metric-label">屏幕</span><strong class="metric-value" id="screen">读取中…</strong></div>
                <div class="metric"><span class="metric-label">像素比</span><strong class="metric-value" id="dpr">读取中…</strong></div>
                <div class="metric"><span class="metric-label">触控点数</span><strong class="metric-value" id="touch">读取中…</strong></div>
                <div class="metric"><span class="metric-label">CPU 逻辑核心</span><strong class="metric-value" id="cores">读取中…</strong></div>
                <div class="metric"><span class="metric-label">设备内存</span><strong class="metric-value" id="memory">读取中…</strong></div>
            </div>
        </article>

        <article class="panel">
            <div class="panel-head"><h2>浏览器能力</h2><span class="panel-caption">不上传结果</span></div>
            <div class="chips" id="capabilities"></div>
        </article>

        <article class="panel wide">
            <div class="panel-head"><h2>已收到的请求头</h2><span class="panel-caption">敏感字段已遮盖</span></div>
            <div class="table-wrap"><table>
                <tbody>
                <?php foreach ($safeHeaders as $name => $value): ?>
                    <tr><th><?= h((string) $name) ?></th><td><?= h((string) $value) ?></td></tr>
                <?php endforeach; ?>
                </tbody>
            </table></div>
        </article>

        <article class="panel wide">
            <div class="panel-head"><h2>User-Agent Client Hints</h2><span class="panel-caption">浏览器支持时显示</span></div>
            <div class="ua"><p class="ua-value" id="client-hints">当前浏览器未提供 User-Agent Client Hints，或正在读取…</p></div>
        </article>
    </section>

    <p class="footer">页面生成时间：<?= h($generatedAt) ?> · 建议在不同环境分别打开并保存报告后对比。</p>
</main>
<div class="toast" id="toast" role="status" aria-live="polite"></div>

<script>
(() => {
    const serverHeaders = <?= json_encode($safeHeaders, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>;
    const generatedAt = <?= json_encode($generatedAt, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>;
    const $ = (id) => document.getElementById(id);
    const text = (id, value) => { $(id).textContent = value ?? '未知'; };
    const yesNo = (value) => value ? '是' : '否';

    const nav = navigator;
    const timezone = (() => {
        try { return Intl.DateTimeFormat().resolvedOptions().timeZone || '未知'; } catch (_) { return '未知'; }
    })();

    text('client-ua', nav.userAgent);
    text('platform', nav.platform || '未知');
    text('language', [nav.language, ...(nav.languages || []).filter((item) => item !== nav.language)].filter(Boolean).join(', '));
    text('timezone', `${timezone} (UTC${new Date().getTimezoneOffset() <= 0 ? '+' : '-'}${String(Math.abs(new Date().getTimezoneOffset()) / 60).padStart(2, '0')}:00)`);
    text('online', yesNo(nav.onLine));
    text('webdriver', yesNo(nav.webdriver));
    text('viewport', `${window.innerWidth} × ${window.innerHeight}`);
    text('screen', `${screen.width} × ${screen.height} / ${screen.colorDepth} bit`);
    text('dpr', window.devicePixelRatio || 1);
    text('touch', nav.maxTouchPoints ?? 0);
    text('cores', nav.hardwareConcurrency || '未知');
    text('memory', nav.deviceMemory ? `${nav.deviceMemory} GB` : '未提供');

    const capabilityChecks = [
        ['Cookie', nav.cookieEnabled],
        ['Local Storage', canUse(() => localStorage.setItem('__ua_test__', '1'), () => localStorage.removeItem('__ua_test__'))],
        ['Session Storage', canUse(() => sessionStorage.setItem('__ua_test__', '1'), () => sessionStorage.removeItem('__ua_test__'))],
        ['IndexedDB', 'indexedDB' in window],
        ['Service Worker', 'serviceWorker' in nav],
        ['WebGL', canUseWebGL()],
        ['PDF Viewer', nav.pdfViewerEnabled === true],
        ['深色模式', matchMedia('(prefers-color-scheme: dark)').matches],
        ['减少动态效果', matchMedia('(prefers-reduced-motion: reduce)').matches],
    ];
    $('capabilities').innerHTML = capabilityChecks.map(([label, enabled]) => `<span class="chip ${enabled ? 'ok' : ''}">${escapeHtml(label)}：${enabled ? '支持' : '不支持 / 未启用'}</span>`).join('');

    function canUse(setter, cleanup) {
        try { setter(); cleanup(); return true; } catch (_) { return false; }
    }

    function canUseWebGL() {
        try {
            const canvas = document.createElement('canvas');
            return Boolean(canvas.getContext('webgl') || canvas.getContext('experimental-webgl'));
        } catch (_) { return false; }
    }

    function escapeHtml(value) {
        return String(value).replace(/[&<>'"]/g, (character) => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;'}[character]));
    }

    const report = {
        generatedAt,
        server: { userAgent: <?= json_encode($serverUserAgent, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) ?>, headers: serverHeaders },
        browser: {
            userAgent: nav.userAgent,
            platform: nav.platform || null,
            language: nav.language || null,
            languages: nav.languages || [],
            timezone,
            timezoneOffsetMinutes: new Date().getTimezoneOffset(),
            online: nav.onLine,
            webdriver: Boolean(nav.webdriver),
            viewport: { width: window.innerWidth, height: window.innerHeight },
            screen: { width: screen.width, height: screen.height, colorDepth: screen.colorDepth, pixelDepth: screen.pixelDepth },
            devicePixelRatio: window.devicePixelRatio || 1,
            maxTouchPoints: nav.maxTouchPoints ?? 0,
            hardwareConcurrency: nav.hardwareConcurrency || null,
            deviceMemoryGB: nav.deviceMemory || null,
            capabilities: Object.fromEntries(capabilityChecks),
        }
    };

    if (nav.userAgentData) {
        const lowEntropy = {
            mobile: nav.userAgentData.mobile,
            platform: nav.userAgentData.platform,
            brands: nav.userAgentData.brands || nav.userAgentData.uaList || [],
        };
        $('client-hints').textContent = JSON.stringify(lowEntropy, null, 2);
        report.browser.userAgentData = lowEntropy;
        if (typeof nav.userAgentData.getHighEntropyValues === 'function') {
            nav.userAgentData.getHighEntropyValues(['architecture', 'bitness', 'model', 'platformVersion', 'uaFullVersion', 'fullVersionList'])
                .then((highEntropy) => {
                    report.browser.userAgentData = { ...lowEntropy, ...highEntropy };
                    $('client-hints').textContent = JSON.stringify(report.browser.userAgentData, null, 2);
                })
                .catch(() => {});
        }
    }

    $('copy-report').addEventListener('click', async () => {
        try {
            await navigator.clipboard.writeText(JSON.stringify(report, null, 2));
            showToast('JSON 报告已复制');
        } catch (_) {
            showToast('复制失败，请检查浏览器权限');
        }
    });

    function showToast(message) {
        const toast = $('toast');
        toast.textContent = message;
        toast.classList.add('show');
        window.setTimeout(() => toast.classList.remove('show'), 2200);
    }
})();
</script>
</body>
</html>
