import test from 'node:test';
import assert from 'node:assert/strict';
import { fixture, key } from './helpers/bundle-fixture.ts';

async function settingsFixture() {
  const f = await fixture(); f.menus[0]();
  const root = f.window.document.querySelector('#nspp-settings')!.shadowRoot!;
  const visibleCards = () => [...root.querySelectorAll<HTMLElement>('.feature-card')].filter(row => !row.hidden);
  return { ...f, root, visibleCards };
}

test('category and enabled filters narrow the catalog; search keeps existing controls and supports multiple words', async () => {
  const f = await settingsFixture();
  try {
    const total = f.visibleCards().length;
    f.root.querySelector<HTMLButtonElement>('[data-category="浏览"]')!.click();
    assert.ok(f.visibleCards().length > 0 && f.visibleCards().length < total);
    assert.ok(f.visibleCards().every(row => row.closest('section')?.dataset.section === '浏览'));
    f.root.querySelector<HTMLButtonElement>('[data-filter="enabled"]')!.click();
    assert.ok(f.visibleCards().every(row => row.dataset.enabled === 'true'));
    const row = f.root.querySelector<HTMLElement>('[data-feature="post-preview"]')!;
    const search = f.root.querySelector<HTMLInputElement>('[type="search"]')!;
    search.value = '预览 移动端'; search.dispatchEvent(new f.window.Event('input'));
    assert.equal(f.root.querySelector('[data-feature="post-preview"]'), row, 'search must not recreate controls');
    assert.ok(f.visibleCards().length > 0);
    assert.equal(f.root.querySelector('[data-category="全部"]')?.getAttribute('aria-current'), 'page');
  } finally { await f.close(); }
});

test('unsaved settings survive close and repeated open; undo clears the draft and unload warning', async () => {
  const f = await settingsFixture();
  try {
    const row = f.visibleCards()[0], id = row.dataset.feature;
    const toggle = row.querySelector<HTMLInputElement>('.feature-toggle')!;
    const initial = toggle.checked; toggle.click();
    assert.match(f.root.querySelector('.settings-footer-hint')!.textContent!, /1 项功能已修改/);
    const unloading = new f.window.Event('beforeunload', { cancelable: true });
    assert.equal(f.window.dispatchEvent(unloading), false);
    f.menus[0]();
    assert.equal(toggle.checked, !initial, 'opening an already-open modal does not replace the draft');
    f.root.querySelector<HTMLButtonElement>('.settings-close')!.click(); f.menus[0]();
    assert.equal(f.root.querySelector<HTMLInputElement>(`[data-feature="${id}"] .feature-toggle`)!.checked, !initial);
    f.root.querySelector<HTMLButtonElement>('[data-filter="modified"]')!.click();
    assert.equal(f.visibleCards().length, 1);
    f.root.querySelector<HTMLButtonElement>('.settings-undo')!.click();
    assert.equal(f.visibleCards().length, 0);
    assert.equal(f.window.dispatchEvent(new f.window.Event('beforeunload', { cancelable: true })), true);
  } finally { await f.close(); }
});

test('settings submit preserves unrelated live settings and validates disabled feature fields correctly', async () => {
  const f = await settingsFixture();
  try {
    const request = f.root.querySelector<HTMLElement>('[data-feature="request-settings"]')!;
    const interval = request.querySelector<HTMLInputElement>('[data-option="requestInterval"]')!;
    interval.value = '9000'; interval.dispatchEvent(new f.window.Event('input'));
    request.querySelector<HTMLInputElement>('.feature-toggle')!.click();
    assert.equal(request.querySelector('fieldset')!.disabled, true);
    const stored = structuredClone(f.storage.get(key)) as Record<string, Record<string, unknown>>;
    stored.attendance.mode = 'random'; f.storage.set(key, stored);
    f.root.querySelector<HTMLButtonElement>('.primary')!.click();
    await new Promise(resolve => setTimeout(resolve, 15));
    const saved = f.storage.get(key) as Record<string, Record<string, unknown>>;
    assert.equal(saved.attendance.mode, 'random');
    assert.equal(saved['request-settings'].enabled, false);
  } finally { await f.close(); }
});

test('invalid enabled fields are revealed before validation; dirty cache clearing cannot discard edits', async () => {
  const f = await settingsFixture();
  try {
    const row = f.root.querySelector<HTMLElement>('[data-feature="request-settings"]')!;
    const interval = row.querySelector<HTMLInputElement>('[data-option="requestInterval"]')!;
    interval.value = '9000'; interval.dispatchEvent(new f.window.Event('input'));
    f.root.querySelector<HTMLButtonElement>('.primary')!.click();
    assert.equal(row.querySelector('fieldset')!.hidden, false);
    assert.equal(f.root.activeElement, interval);
    assert.equal((f.storage.get(key) as Record<string, Record<string, unknown>>)['request-settings'].requestInterval, 0);
    [...f.root.querySelectorAll<HTMLButtonElement>('.data-tools button')].find(button => button.textContent === '清空缓存')!.click();
    assert.match(f.root.querySelector('.toast-message')!.textContent!, /先保存或撤销/);
  } finally { await f.close(); }
});
