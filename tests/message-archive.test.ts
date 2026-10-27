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

test('a local optimistic echo reconciles with a server acknowledgement in the same batch', async () => {
  const archive = createMessageArchive(31);
  const local: Message = { local_id: 'temp-31', after_id: 40, sender_id: 31, receiver_id: 32, content: 'hello', created_at: '2026-09-14T00:00:00Z' };
  const server: Message = { id: 41, sender_id: 31, receiver_id: 32, content: 'hello', created_at: '2026-09-14T00:00:01Z' };
  try {
    const merged = await archive.merge(32, 'Peer', [local, server]);
    assert.equal(merged.length, 1);
    assert.equal(merged[0].id, 41);
    assert.deepEqual((await archive.messages(32)).map(message => message.id), [41]);
  } finally { archive.close(); }
});

test('bulk conversation import handles multiple peers, stale messages and account isolation', async () => {
  const archive = createMessageArchive(47);
  const other = createMessageArchive(48);
  const message = (id: number, peer: number, created_at: string): Message => ({
    id, sender_id: peer, receiver_id: 47, sender_name: `User ${peer}`,
    content: `message ${id}`, created_at, viewed: false,
  });
  try {
    const old = message(101, 60, '2026-09-14T00:00:00Z');
    const latest = message(102, 60, '2026-09-14T00:10:00Z');
    const second = message(201, 61, '2026-09-14T00:05:00Z');
    const foreign: Message = { id: 300, sender_id: 48, receiver_id: 61, content: 'foreign', created_at: '2026-09-14T00:12:00Z' };
    const contacts = await archive.mergeList([latest, second, old, foreign]);
    assert.equal(contacts.length, 2);
    assert.equal(contacts.find(row => row.id === 60)?.latest.id, 102, 'unsorted list selects the true latest message');
    assert.equal(contacts.find(row => row.id === 60)?.unread, true);
    assert.deepEqual((await archive.messages(60)).map(row => row.id), [101, 102]);
    assert.deepEqual((await archive.messages(61)).map(row => row.id), [201]);
    assert.deepEqual(await other.contacts(), []);
    assert.deepEqual(await other.messages(61), []);
    await archive.mergeList([old, old, second]);
    assert.deepEqual((await archive.messages(60)).map(row => row.id), [101, 102], 'repeat import preserves existing messages');
    assert.equal((await archive.contacts()).find(row => row.id === 60)?.latest.id, 102);
  } finally { archive.close(); other.close(); }
});
