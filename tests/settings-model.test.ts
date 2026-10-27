import test from 'node:test';
import assert from 'node:assert/strict';
import type { Feature } from '../src/core/types.ts';
import { changedFeatures, matchesSearch, mergeSettings } from '../src/settings/model.ts';

const features: Feature[] = [{ id: 'reader', title: '', description: '', group: '', defaults: { enabled: true, pages: 6, title: '' }, mount() {} }];
const baseline = { reader: { enabled: true, pages: 6, title: '' } };
test('saving a draft merges changed fields and preserves changes from another panel', () => {
  const latest = { reader: { enabled: false, pages: 6, title: 'from another panel' } };
  const draft = { reader: { enabled: true, pages: 10, title: '' } };
  assert.deepEqual(mergeSettings(features, baseline, draft, latest), { reader: { enabled: false, pages: 10, title: 'from another panel' } });
  assert.equal(latest.reader.pages, 6, 'merge must not mutate the latest snapshot');
  assert.deepEqual(mergeSettings(features, baseline, baseline, latest), latest, 'an unchanged draft never reverts live settings');
});
test('changed features compare actual values and clear when edits are undone', () => {
  assert.deepEqual([...changedFeatures(features, baseline, { reader: { title: '', pages: 6, enabled: true } })], []);
  assert.deepEqual([...changedFeatures(features, baseline, { reader: { title: '', pages: 0, enabled: false } })], ['reader']);
});
test('settings search supports multiple words, whitespace and case insensitive queries', () => {
  assert.ok(matchesSearch('nodeseek 帖子预览 手机点击', ' NODESEEK  手机 '));
  assert.ok(!matchesSearch('nodeseek 帖子预览 手机点击', '手机 消息'));
  assert.ok(matchesSearch('任意功能', '  '));
});
