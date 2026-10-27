import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Window } from 'happy-dom';
import { createMessageArchive, type Message } from '../src/features/messages-storage.ts';

test('clear archive only removes the signed-in account, preserving another user', async () => {
  const sandbox = new Window({ url: 'https://www.nodeseek.com' });
  const context = sandbox as unknown as { indexedDB: IDBFactory; IDBKeyRange: typeof IDBKeyRange };
  const oldDB = Object.getOwnPropertyDescriptor(globalThis, 'indexedDB');
  const oldRange = Object.getOwnPropertyDescriptor(globalThis, 'IDBKeyRange');
  Object.defineProperty(globalThis, 'indexedDB', { configurable: true, value: context.indexedDB });
  Object.defineProperty(globalThis, 'IDBKeyRange', { configurable: true, value: context.IDBKeyRange });
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
    if (oldDB) Object.defineProperty(globalThis, 'indexedDB', oldDB); else Reflect.deleteProperty(globalThis, 'indexedDB');
    if (oldRange) Object.defineProperty(globalThis, 'IDBKeyRange', oldRange); else Reflect.deleteProperty(globalThis, 'IDBKeyRange');
    await sandbox.happyDOM.abort();
  }
});
