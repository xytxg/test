import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import type { Window } from 'happy-dom';
import { bundle, key, fixture, waitFor } from './helpers/bundle-fixture.ts';

test('bundle is self-contained, scoped to forum hosts and has no remote require', () => {
  assert.match(bundle, /@match\s+https:\/\/www\.nodeseek\.com\/\*/);
  assert.doesNotMatch(bundle, /@match\s+\*:\/\/\*\/\*/);
  assert.doesNotMatch(bundle, /@require/);
  assert.match(bundle, /@noframes/);
});

test('manual update checks read metadata and open an update link only for a newer release', async () => {
  const requests: { url: string; anonymous: boolean; nocache: boolean; headers: Record<string, string> }[] = [];
  let version = '1.0.0';
  const f = await fixture({}, '', '/', undefined, window => {
    Object.assign(window, {
      GM_xmlhttpRequest: (options: typeof requests[number] & { onload(response: { status: number; responseText: string }): void }) => {
        requests.push(options);
        setTimeout(() => options.onload({ status: 200, responseText: `// ==UserScript==\n// @namespace nodeseek-plus-plus-xy-test\n// @version ${version}\n// ==/UserScript==` }), 0);
        return { abort() {} };
      },
    });
  }, true);
  try {
    await new Promise(resolve => setTimeout(resolve, 10));
    requests.length = 0; version = '99.999.9999';
    f.menus[0]();
    const root = f.window.document.querySelector('#nspp-settings')!.shadowRoot!;
    const button = root.querySelector<HTMLButtonElement>('.check-update')!;
    button.click(); button.click();
    await new Promise(resolve => setTimeout(resolve, 30));
    assert.equal(requests.length, 1);
    assert.equal(requests[0].url.split('?')[0], 'https://raw.githubusercontent.com/xytxg/test/main/dist/nodeseek-plus-plus.meta.js');
    assert.ok(new URL(requests[0].url).searchParams.get('_'));
    assert.equal(requests[0].nocache, true);
    assert.match(requests[0].headers['Cache-Control'], /no-store/);
    assert.equal(requests[0].headers.Pragma, 'no-cache');
    assert.equal(requests[0].anonymous, true);
    const dialog = f.window.document.querySelector<HTMLDialogElement>('.nspp-update-notice')!;
    assert.equal(dialog.open, true);
    assert.match(dialog.textContent!, /99\.999\.9999/);
    assert.equal(dialog.querySelector<HTMLAnchorElement>('.nspp-update-github')!.href, 'https://github.com/xytxg/test');
    const install = dialog.querySelector<HTMLAnchorElement>('.nspp-update-install')!;
    assert.equal(install.href, 'https://raw.githubusercontent.com/xytxg/test/main/dist/nodeseek-plus-plus.user.js');
    assert.equal(install.target, '_blank');
    dialog.close('cancel');
    await new Promise(resolve => setTimeout(resolve, 10));
    assert.equal(button.disabled, false);
    version = '1.0.0'; button.click();
    await new Promise(resolve => setTimeout(resolve, 30));
    assert.equal(requests.length, 2);
    assert.notEqual(requests[0].url, requests[1].url, 'each manual check bypasses URL caches');
    assert.equal(f.window.document.querySelector('.nspp-update-notice'), null);
    assert.match(root.querySelector('.toast-message')!.textContent!, /当前已是最新版本/);
  } finally { await f.close(); }
});

test('automatic update checks use shared cache while manual checks still force a refresh', async () => {
  const shared = new Map<string, unknown>([
    [key, { attendance: { enabled: false }, monitor: { enabled: false }, 'notification-categories': { enabled: false } }],
    ['nspp:script-update', { checkedAt: Date.now() - 3600_000, version: '1.0.0' }],
    ['nspp:lock:www.nodeseek.com:script-update', { started: Date.now(), until: Date.now() + 120000, owner: 'another-page' }],
  ]);
  const requests: string[] = [];
  const notifications: { title: string; text: string; url: string }[] = [];
  let version = '99.999.9999';
  const setup = (window: Window) => {
    Object.defineProperty(window.document, 'hidden', { configurable: true, value: true });
    Object.assign(window, {
      GM_notification: (details: typeof notifications[number]) => notifications.push(details),
      GM_xmlhttpRequest: (options: { url: string; onload(response: { status: number; responseText: string }): void }) => {
        requests.push(options.url);
        queueMicrotask(() => options.onload({ status: 200, responseText: `// ==UserScript==\n// @namespace nodeseek-plus-plus-xy-test\n// @version ${version}\n// ==/UserScript==` }));
        return { abort() {} };
      },
    });
  };
  const first = await fixture({}, '', '/', shared, setup, true);
  let second: Awaited<ReturnType<typeof fixture>> | undefined;
  try {
    await new Promise(resolve => setTimeout(resolve, 15));
    assert.equal(requests.length, 1, 'a stale cache fetches once');
    assert.equal(notifications.length, 1, 'hidden pages still notify of genuine updates');
    assert.equal(notifications[0].url, 'https://raw.githubusercontent.com/xytxg/test/main/dist/nodeseek-plus-plus.user.js');
    Object.defineProperty(first.window.document, 'hidden', { configurable: true, value: false });
    first.window.document.dispatchEvent(new first.window.Event('visibilitychange'));
    await new Promise(resolve => setTimeout(resolve, 15));
    assert.equal(requests.length, 1, 'focus uses cached update metadata');
    assert.ok(first.window.document.querySelector<HTMLDialogElement>('.nspp-update-notice')?.open);
    const restored = new first.window.Event('pageshow'); Object.defineProperty(restored, 'persisted', { value: true });
    first.window.dispatchEvent(restored);
    await new Promise(resolve => setTimeout(resolve, 15));
    assert.equal(requests.length, 1, 'BFCache restore does not refetch fresh metadata');
    first.window.document.querySelector<HTMLDialogElement>('.nspp-update-notice')!.close('cancel');
    second = await fixture({}, '', '/page-2', shared, setup, true);
    await new Promise(resolve => setTimeout(resolve, 15));
    assert.equal(requests.length, 1, 'another page reuses the persisted metadata cache');
    assert.equal(notifications.length, 1);
    version = '99.999.9999.1';
    Object.defineProperty(second.window.document, 'hidden', { configurable: true, value: false });
    second.window.document.dispatchEvent(new second.window.Event('visibilitychange'));
    await new Promise(resolve => setTimeout(resolve, 15));
    assert.equal(requests.length, 1, 'automatic checks cannot see new versions until cache expires');
    second.menus[0]();
    const root = second.window.document.querySelector('#nspp-settings')!.shadowRoot!;
    root.querySelector<HTMLButtonElement>('.check-update')!.click();
    await new Promise(resolve => setTimeout(resolve, 35));
    assert.equal(requests.length, 2, 'manual check bypasses shared cache');
    assert.equal(new Set(requests).size, 2, 'requests that are sent still bypass HTTP caches');
    assert.equal(notifications.length, 2, 'manual refresh detects a new version');
    assert.match(notifications[1].text, /99\.999\.9999\.1/);
  } finally { await first.close(); await second?.close(); }
});

test('site fast-nav buttons move into the toolbar and forward clicks to the native controls', async () => {
  const html = '<div id="fast-nav-button-group"><div id="back-to-top" class="nav-item-btn" style="display: flex;"></div><div id="back-to-parent" class="nav-item-btn" style="display: none;"></div><div id="back-to-bottom" class="nav-item-btn" style="display: flex;"></div></div>';
  const f = await fixture({}, html);
  try {
    const doc = f.window.document;
    await waitFor(() => doc.documentElement.hasAttribute('data-nspp-fast-nav'));
    const proxy = (id: string) => doc.querySelector<HTMLButtonElement>(`#nspp-tools [data-nspp-fast-nav="${id}"]`)!;
    assert.equal(proxy('back-to-top').hidden, false);
    assert.equal(proxy('back-to-parent').hidden, true);
    assert.equal(proxy('back-to-bottom').hidden, false);
    let clicked = '';
    doc.getElementById('back-to-bottom')!.addEventListener('click', () => { clicked = 'bottom'; });
    proxy('back-to-bottom').click();
    assert.equal(clicked, 'bottom');
    doc.getElementById('back-to-parent')!.setAttribute('style', 'display: flex;');
    await waitFor(() => !proxy('back-to-parent').hidden);
    doc.getElementById('fast-nav-button-group')!.remove();
    await waitFor(() => !doc.documentElement.hasAttribute('data-nspp-fast-nav'));
    await waitFor(() => proxy('back-to-top').hidden && proxy('back-to-bottom').hidden);
  } finally { await f.close(); }
});

test('boot with monitoring disabled makes no API calls; repeated boot does not duplicate the UI', async () => {
  const f = await fixture({}, '<ul class="post-list"><li class="post-list-item"><div class="post-title"><a href="/post-42-1">Test post</a></div></li></ul>');
  try {
    assert.equal(f.window.document.querySelectorAll('#nspp-settings').length, 1);
    assert.deepEqual(f.menuLabels, ['NodeSeek++ 设置', '签到', 'NodeSeek 热榜', '阅读历史', '回帖足迹']);
    assert.equal(f.requests.length, 0);
    f.window.eval(bundle);
    assert.equal(f.window.document.querySelectorAll('#nspp-settings').length, 1);
    assert.equal(f.window.document.querySelectorAll('#nspp-tools').length, 1);
    f.menus[0]();
    const root = f.window.document.querySelector('#nspp-settings')!.shadowRoot!;
    assert.equal(root.querySelector('dialog')!.open, true);
    assert.ok(root.querySelectorAll('article').length >= 20);
  } finally { await f.close(); }
});

test('missing GM APIs do not abort startup or pretend settings were saved', async () => {
  const f = await fixture({}, '', '/', undefined, window => {
    Object.assign(window, { GM_getValue: undefined, GM_setValue: undefined, GM_registerMenuCommand: undefined, unsafeWindow: undefined });
  });
  try {
    const root = f.window.document.querySelector('#nspp-settings')!.shadowRoot!;
    f.window.document.querySelector<HTMLButtonElement>('[data-nspp-settings-launcher]')!.click();
    assert.equal(root.querySelector('dialog')!.open, true);
    assert.equal((root.querySelector('.primary') as HTMLButtonElement).disabled, true);
    assert.match(root.querySelector('.status')!.textContent!, /油猴存储未就绪/);
    assert.ok(f.window.document.querySelector('#nspp-tools'));
    assert.equal(f.window.localStorage.length, 0);
  } finally { await f.close(); }
});

test('async-only GM.* managers (iOS Userscripts) load, save settings and make requests', async () => {
  const saved: string[] = [], requested: string[] = [];
  let store: Map<string, unknown> | undefined;
  const f = await fixture({}, '', '/', undefined, window => {
    store = new Map([[key, { attendance: { enabled: true, automatic: false }, monitor: { enabled: false }, 'notification-categories': { enabled: false }, 'request-settings': { enabled: true, requestInterval: 0 } }]]);
    Object.assign(window, {
      GM_getValue: undefined, GM_setValue: undefined, GM_xmlhttpRequest: undefined,
      GM: {
        getValue: async (name: string) => structuredClone(store!.get(name)),
        setValue: async (name: string, value: unknown) => { saved.push(name); store!.set(name, structuredClone(value)); },
        listValues: async () => [...store!.keys()],
        xmlHttpRequest: (options: { url: string; onerror(): void }) => { requested.push(options.url); queueMicrotask(() => options.onerror()); return { abort() {} }; },
      },
    });
  }, true);
  try {
    const doc = f.window.document;
    assert.ok(doc.querySelector('#nspp-tools'));
    assert.equal(doc.querySelector('[data-nspp-monitor-launcher]'), null, 'stored settings (monitor off) were read through GM.getValue');
    const root = doc.querySelector('#nspp-settings')!.shadowRoot!;
    doc.querySelector<HTMLButtonElement>('[data-nspp-settings-launcher]')!.click();
    assert.doesNotMatch(root.querySelector('.status')!.textContent!, /油猴存储未就绪/);
    const save = root.querySelector<HTMLButtonElement>('.primary')!;
    assert.equal(save.disabled, false);
    save.click();
    await new Promise(resolve => setTimeout(resolve, 10));
    assert.ok(saved.includes(key), 'settings persisted through GM.setValue');
    root.querySelector<HTMLButtonElement>('.check-update')!.click();
    await new Promise(resolve => setTimeout(resolve, 10));
    assert.ok(requested.some(url => url.includes('nodeseek-plus-plus.meta.js')), 'cross-origin requests fall back to GM.xmlHttpRequest');
  } finally { await f.close(); }
});

test('request concurrency and default interval settings are searchable and saved', async () => {
  let calls = 0;
  const f = await fixture({ 'request-settings': { enabled: true, maxConcurrent: 2 }, 'official-blocklist': { enabled: false } }, '<div class="author-info"><a href="/space/123">Alice</a><a href="/space/124">Bob</a></div>', '/', undefined, window => {
    window.fetch = (async () => {
      calls++;
      return new window.Response(JSON.stringify({ success: true, detail: { created_at: '2020-01-01' } }), { headers: { 'Content-Type': 'application/json' } });
    }) as typeof window.fetch;
  });
  try {
    await new Promise(resolve => setTimeout(resolve, 50));
    assert.equal(calls, 1, 'default 200ms interval separates request starts');
    await new Promise(resolve => setTimeout(resolve, 220));
    assert.equal(calls, 2);
    f.menus[0]();
    const root = f.window.document.querySelector('#nspp-settings')!.shadowRoot!;
    const search = root.querySelector<HTMLInputElement>('input[type="search"]')!;
    search.value = '最大并发请求数'; search.dispatchEvent(new f.window.Event('input'));
    assert.equal(root.querySelectorAll('article').length, 1);
    assert.match(root.querySelector('article')!.textContent!, /接口请求并发/);
    assert.ok(root.querySelector('article > .feature-options'));
    assert.equal(root.querySelector('details'), null);
    assert.equal(root.querySelector<HTMLInputElement>('input[type="number"]')!.value, '2');
    const inputs = root.querySelectorAll<HTMLInputElement>('input[type="number"]');
    assert.equal(inputs[0].min, '1'); assert.equal(inputs[0].max, '10');
    assert.equal(inputs[1].value, '200'); assert.equal(inputs[1].min, '0'); assert.equal(inputs[1].max, '5000');
    inputs[1].value = '350'; inputs[1].dispatchEvent(new f.window.Event('input'));
    root.querySelector('form')!.dispatchEvent(new f.window.Event('submit', { cancelable: true }));
    assert.equal((f.storage.get(key) as Record<string, Record<string, unknown>>)['request-settings'].requestInterval, 350);
  } finally { await f.close(); }
});

test('settings categories are anchors, scroll updates selection and search filters both panes', async () => {
  const f = await fixture();
  try {
    f.menus[0]();
    const root = f.window.document.querySelector('#nspp-settings')!.shadowRoot!;
    const nav = [...root.querySelectorAll<HTMLAnchorElement>('.categories a')];
    assert.deepEqual(nav.map(link => link.textContent), ['浏览', '用户', '工具', '其他']);
    assert.equal(nav[0].getAttribute('aria-current'), 'location');
    const content = root.querySelector('.content')!;
    const sections = [...content.querySelectorAll('section')];
    Object.defineProperty(content, 'getBoundingClientRect', { value: () => ({ top: 0 }) });
    sections.forEach((section, i) => Object.defineProperty(section, 'getBoundingClientRect', { value: () => ({ top: (i - 2) * 100 }) }));
    content.dispatchEvent(new f.window.Event('scroll'));
    assert.equal(nav[2].getAttribute('aria-current'), 'location');
    const search = root.querySelector<HTMLInputElement>('input[type="search"]')!;
    search.value = '黑名单'; search.dispatchEvent(new f.window.Event('input'));
    assert.equal(root.querySelectorAll('.categories a').length, 1);
    assert.equal(root.querySelector('.categories a')!.textContent, '用户');
    search.value = 'github'; search.dispatchEvent(new f.window.Event('input'));
    assert.deepEqual([...root.querySelectorAll('.categories a')].map(link => link.textContent), ['其他']);
    assert.ok(root.querySelector('.about-links a[href="https://github.com/xytxg/test"]'));
  } finally { await f.close(); }
});

test('busy controls use opaque motion feedback and loading text uses SweepShine', () => {
  const css = readFileSync(new URL('../src/loading.css', import.meta.url), 'utf8');
  const textShine = ['.nspp-sweep-shine, [aria-busy="true"].nspp-sweep-shine', '.nspp-user-badges[aria-busy="true"]'];
  // Inspect declaration blocks, including blocks nested in reduced-motion media rules.
  const blocks = [...css.replace(/\/\*[\s\S]*?\*\//g, '').matchAll(/([^{}]+)\{([^{}]*)\}/g)];
  for (const [, selector, declarations] of blocks) {
    if (/text-fill-color:\s*transparent|background-clip:\s*text/.test(declarations)) {
      assert.ok(textShine.includes(selector.trim()), `text clipping is restricted to loading text: ${selector.trim()}`);
    }
  }
  const base = blocks.find(([, selector]) => selector.trim() === '[aria-busy="true"], .nspp-skeleton-shine');
  assert.ok(base);
  assert.match(base[2], /-webkit-text-fill-color:\s*currentColor/);
  const shine = blocks.find(([, selector]) => selector.trim() === textShine[0]);
  assert.ok(shine);
  assert.match(shine[2], /background-clip:\s*text[^}]*-webkit-text-fill-color:\s*transparent[^}]*animation: nspp-sweep-shine/);
  assert.match(css, /\.nspp-sweep-shine \* \{\s*-webkit-text-fill-color:\s*currentColor/, 'nested elements inside shining text stay visible');
  assert.match(css, /\[aria-busy="true"\]:has\(> \.nspp-sweep-shine\) \{[^}]*background-image:\s*none/, 'a shining label replaces the control sweep');
  assert.match(css, /@media\s*\(prefers-reduced-motion:\s*reduce\)\s*\{\s*\.nspp-sweep-shine, \[aria-busy="true"\]\.nspp-sweep-shine\s*\{[^}]*animation:\s*none;[^}]*-webkit-text-fill-color:\s*currentColor/);
  assert.match(css, /@media\s*\(prefers-reduced-motion:\s*reduce\)\s*\{\s*\.nspp-user-badges\[aria-busy="true"\]\s*\{[^}]*background-image:\s*none;[^}]*-webkit-text-fill-color:\s*currentColor/);
  assert.match(css, /opacity: 1 !important/);
  assert.match(css, /\.nspp-action\[aria-busy="true"\] > svg[^}]+animation: nspp-attendance-working/);
});

test('AI launcher requires complete enabled configuration and keeps configuration in settings', async () => {
  const configured = { enabled: true, url: 'https://example.com/v1/chat/completions', model: 'test-model', apiKey: 'test-key' };
  for (const options of [{}, { ...configured, enabled: false }, { ...configured, apiKey: '' }, { ...configured, model: '' }, { ...configured, url: 'http://example.com' }]) {
    const f = await fixture({ 'ai-polish': options });
    try {
      assert.equal(f.window.document.querySelector('[data-nspp-ai-launcher]'), null);
      f.menus[0]();
      assert.match(f.window.document.querySelector('#nspp-settings')!.shadowRoot!.textContent!, /AI 写作助手/);
    } finally { await f.close(); }
  }
  const f = await fixture({ 'ai-polish': configured });
  try {
    f.window.document.querySelector<HTMLButtonElement>('[data-nspp-ai-launcher]')!.click();
    const panel = f.window.document.querySelector('.nspp-ai-dialog')!;
    assert.equal(panel.querySelector('h2')!.textContent, 'AI 写作助手');
    assert.ok(panel.querySelector('[data-nspp-ai]'));
    assert.ok(panel.querySelector('[aria-label="AI 写作正文"]'));
    assert.equal(panel.querySelector('input[type="password"]'), null);
    assert.equal([...panel.querySelectorAll('button')].some(button => button.textContent === '配置'), false);
    assert.equal(f.requests.length, 0);
  } finally { await f.close(); }
});

test('async-only iOS storage does not reload settings before the slow write completes', async () => {
  let finish: (() => void) | undefined;
  const store = new Map<string, unknown>([[key, { attendance: { enabled: true, automatic: false }, monitor: { enabled: false }, 'notification-categories': { enabled: false }, 'request-settings': { enabled: true, requestInterval: 0 } }]]);
  const f = await fixture({}, '', '/', undefined, window => {
    Object.assign(window, {
      GM_getValue: undefined, GM_setValue: undefined,
      GM: {
        getValue: async (name: string) => structuredClone(store.get(name)),
        listValues: async () => [...store.keys()],
        setValue: (name: string, value: unknown) => {
          if (name !== key) { store.set(name, structuredClone(value)); return Promise.resolve(); }
          return new Promise<void>(resolve => { finish = () => { store.set(name, structuredClone(value)); resolve(); }; });
        },
      },
    });
  });
  try {
    f.window.document.querySelector<HTMLButtonElement>('[data-nspp-settings-launcher]')!.click();
    const root = f.window.document.querySelector('#nspp-settings')!.shadowRoot!;
    const save = root.querySelector<HTMLButtonElement>('.primary')!;
    save.click();
    await waitFor(() => typeof finish === 'function');
    assert.equal(save.disabled, true, 'save stays busy until GM.setValue resolves');
    assert.deepEqual(store.get(key), { attendance: { enabled: true, automatic: false }, monitor: { enabled: false }, 'notification-categories': { enabled: false }, 'request-settings': { enabled: true, requestInterval: 0 } });
    finish!();
    await new Promise(resolve => setTimeout(resolve, 20));
    assert.ok(store.get(key));
  } finally { finish?.(); await f.close(); }
});

test('a fresh cached current version skips automatic network requests', async () => {
  const store = new Map<string, unknown>([[key, { attendance: { enabled: false }, monitor: { enabled: false }, 'notification-categories': { enabled: false } }], ['nspp:script-update', { checkedAt: Date.now(), version: '26.1027.1734' }]]);
  const f = await fixture({}, '', '/', store, undefined, true);
  try {
    await new Promise(resolve => setTimeout(resolve, 15));
    assert.equal(f.requests.length, 0);
    assert.ok(!f.window.document.querySelector('.nspp-update-notice'));
  } finally { await f.close(); }
});

test('scoped DOM watchers ignore unrelated insertions yet process newly appended native posts', async () => {
  const f = await fixture({ 'official-blocklist': { enabled: false }, 'user-level': { enabled: false } },
    '<ul class="post-list"><li class="post-list-item"><div class="post-title"><a href="/post-11-1">First</a></div></li></ul>');
  try {
    const doc = f.window.document;
    // Finish the initial 100ms coalesced DOM pass before measuring later changes.
    await new Promise(resolve => setTimeout(resolve, 170));
    const original = doc.querySelectorAll.bind(doc);
    let scans = 0;
    doc.querySelectorAll = ((selector: string) => {
      if (selector === '.post-list-item .post-title a') scans++;
      return original(selector);
    }) as typeof doc.querySelectorAll;
    doc.body.append(doc.createElement('aside'));
    await new Promise(resolve => setTimeout(resolve, 160));
    assert.equal(scans, 0, 'unrelated DOM insertions should not rescan post-preview links');
    const list = doc.querySelector('.post-list')!;
    list.insertAdjacentHTML('beforeend', '<li class="post-list-item"><div class="post-title"><a href="/post-12-1">Fresh</a></div></li>');
    await waitFor(() => !!list.querySelector('.post-list-item:last-child .nspp-title-preview'));
    assert.ok(scans > 0, 'a new post must still be enhanced');
  } finally { await f.close(); }
});

test('settings UX exposes descriptions and prevents Enter in search from saving the whole form', async () => {
  const f = await fixture({ 'official-blocklist': { enabled: false }, monitor: { enabled: false } }, '');
  try {
    f.window.document.querySelector<HTMLButtonElement>('[data-nspp-settings-launcher]')!.click();
    const root = f.window.document.querySelector('#nspp-settings')!.shadowRoot!;
    assert.match(root.querySelector('.enabled-count')!.textContent!, /已启用/);
    assert.ok(root.querySelector('.feature-copy small')?.textContent?.trim(), 'feature explanations should be readable without a tooltip');
    assert.match(root.querySelector('style')!.textContent!, /\.feature-copy/);
    const search = root.querySelector<HTMLInputElement>('input[type="search"]')!;
    search.value = '自动翻页'; search.dispatchEvent(new f.window.Event('input'));
    assert.match(root.querySelector('.content')!.textContent!, /自动翻页/);
    const enter = new f.window.KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true });
    assert.equal(search.dispatchEvent(enter), false, 'pressing Enter in search should not submit');
    assert.ok(root.querySelector<HTMLDialogElement>('dialog')!.open);
    const escape = new f.window.KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true });
    assert.equal(search.dispatchEvent(escape), false, 'Escape clears an active search without closing settings');
    assert.equal(search.value, '');
    assert.ok(root.querySelector<HTMLDialogElement>('dialog')!.open);
  } finally { await f.close(); }
});

test('redesigned settings show a brand, result count, toggles, and follow live forum themes', async () => {
  const f = await fixture();
  try {
    f.menus[0]();
    const doc = f.window.document;
    const root = doc.querySelector('#nspp-settings')!.shadowRoot!;
    assert.equal(root.querySelector('.settings-mark')?.textContent, 'N+');
    assert.match(root.querySelector('.settings-results')!.textContent!, /项功能/);
    const feature = root.querySelector<HTMLElement>('.feature-card')!;
    const toggle = feature.querySelector<HTMLInputElement>('.feature-toggle')!;
    assert.equal(feature.dataset.enabled, String(toggle.checked));
    toggle.click();
    assert.equal(feature.dataset.enabled, String(toggle.checked));
    const search = root.querySelector<HTMLInputElement>('input[type="search"]')!;
    search.value = '不存在的功能搜索词'; search.dispatchEvent(new f.window.Event('input'));
    assert.match(root.querySelector('.settings-results')!.textContent!, /0 项匹配/);
    assert.match(root.querySelector('.settings-empty')!.textContent!, /没有找到/);
    search.value = ''; search.dispatchEvent(new f.window.Event('input'));
    doc.body.classList.add('dark-layout');
    await new Promise(resolve => setTimeout(resolve, 0));
    assert.equal(doc.querySelector('#nspp-settings')!.hasAttribute('data-dark'), true);
    doc.body.classList.remove('dark-layout');
    await new Promise(resolve => setTimeout(resolve, 0));
    assert.equal(doc.querySelector('#nspp-settings')!.hasAttribute('data-dark'), false);
  } finally { await f.close(); }
});
