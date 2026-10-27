import { test } from 'node:test';
import assert from 'node:assert/strict';
import 'fake-indexeddb/auto';
import { createMessageArchive, type Message } from '../src/features/messages-storage.ts';

test('clear archive only removes the signed-in account, preserving another user', async () => {
  const first = createMessageArchive(7);
  const second = createMessageArchive(8);
  const entry = (sender_id: number): Message => ({ id: sender_id, sender_id, receiver_id: 9, content: 'private', created_at: '2026-09-14T00:00:00Z' });
  try {
    await first.merge(9, 'Peer', [entry(7)]);
    await second.merge(9, 'Peer', [entry(8)]);
    assert.equal((await first.messages(9)).length, 1);
    assert.equal((await second.messages(9)).length, 1);
    await first.clearAccount();
    assert.deepEqual(await first.messages(9), []);
    assert.equal((await first.contacts()).length, 0);
    assert.equal((await second.messages(9)).length, 1);
    assert.equal((await second.contacts()).length, 1);
  } finally {
    first.close(); second.close();
  }
});
