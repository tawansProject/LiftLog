import { test } from 'node:test';
import assert from 'node:assert/strict';
import { syncOnce, hashOf, stableStringify, pendingChanges } from '../src/lib/sync.js';

// In-memory stand-in for the Supabase `liftlog_items` table, scoped to one user
// (row-level security does that on the real server). Server time advances per write.
function fakeDb(userId, shared = { rows: [], clock: 1000 }) {
  const iso = (n) => new Date(n).toISOString();
  const from = () => {
    const q = { filters: [], range: null };
    const run = () => {
      let rows = shared.rows.filter((r) => r.user_id === userId);
      for (const f of q.filters) rows = rows.filter(f);
      rows = rows.sort((a, b) => a.updated_at.localeCompare(b.updated_at));
      if (q.range) rows = rows.slice(q.range[0], q.range[1] + 1);
      // jsonb comes back with its keys reordered.
      return { data: rows.map((r) => ({ ...r, data: r.data && JSON.parse(stableStringify(r.data)) })), error: null };
    };
    const b = {
      select() { return b; },
      order() { return b; },
      range(a, z) { q.range = [a, z]; return b; },
      gt(col, v) { q.filters.push((r) => r[col] > v); return b; },
      then(res, rej) { return Promise.resolve(run()).then(res, rej); },
      upsert(rows) {
        const written = rows.map((row) => {
          shared.clock += 1000;
          const existing = shared.rows.find((r) => r.user_id === userId && r.kind === row.kind && r.id === row.id);
          const next = { user_id: userId, ...row, data: structuredClone(row.data), updated_at: iso(shared.clock) };
          if (existing) Object.assign(existing, next); else shared.rows.push(next);
          return next;
        });
        return { select: () => Promise.resolve({ data: written.map((w) => ({ updated_at: w.updated_at })), error: null }) };
      },
    };
    return b;
  };
  return { from, shared };
}

function device(initial) {
  let state = { templates: [], records: [], settings: { restBetweenSets: 90 }, ...initial };
  return {
    get: () => state,
    set: (patch) => { state = { ...state, ...patch }; },
    edit: (patch) => { state = { ...state, ...patch }; },
  };
}

const plan = (id, name) => ({ id, name, items: [], updatedAt: 1 });
const record = (id, startedAt) => ({ id, name: 'Session', startedAt, exercises: [] });

test('hash ignores key order', () => {
  assert.equal(hashOf({ a: 1, b: [1, { c: 2, d: 3 }] }), hashOf({ b: [1, { d: 3, c: 2 }], a: 1 }));
  assert.notEqual(hashOf({ a: 1 }), hashOf({ a: 2 }));
});

test('first sign-in uploads local data; the account keeps its settings', async () => {
  const shared = { rows: [], clock: 1000 };
  const db = fakeDb('u1', shared);
  // The account already has settings from another device.
  await db.from('liftlog_items').upsert([{ kind: 'settings', id: 'main', data: { restBetweenSets: 120 }, deleted: false }]).select();

  const phone = device({ templates: [plan('p1', 'Push')], records: [record('r1', 5)] });
  const res = await syncOnce({ db, userId: 'u1', ...phone });
  assert.equal(phone.get().settings.restBetweenSets, 120, 'account settings win over this device defaults');
  assert.deepEqual(shared.rows.filter((r) => r.kind !== 'settings').map((r) => r.id).sort(), ['p1', 'r1']);
  assert.ok(res.pushed >= 2);

  const again = await syncOnce({ db, userId: 'u1', ...phone });
  assert.equal(again.pushed, 0, 'nothing to upload when nothing changed');
});

test('changes and deletions flow between two devices', async () => {
  const shared = { rows: [], clock: 1000 };
  const a = device({ templates: [plan('p1', 'Push')], records: [record('r1', 5), record('r2', 6)] });
  const b = device();
  await syncOnce({ db: fakeDb('u1', shared), userId: 'u1', ...a });
  await syncOnce({ db: fakeDb('u1', shared), userId: 'u1', ...b });
  assert.deepEqual(b.get().templates.map((t) => t.name), ['Push']);
  assert.equal(b.get().records.length, 2);

  // B renames the plan and deletes a session.
  b.edit({ templates: [{ ...b.get().templates[0], name: 'Push day' }], records: b.get().records.filter((r) => r.id !== 'r1') });
  await syncOnce({ db: fakeDb('u1', shared), userId: 'u1', ...b });
  assert.equal(shared.rows.find((r) => r.id === 'r1').deleted, true, 'deletion is uploaded as a tombstone');

  await syncOnce({ db: fakeDb('u1', shared), userId: 'u1', ...a });
  assert.deepEqual(a.get().templates.map((t) => t.name), ['Push day']);
  assert.deepEqual(a.get().records.map((r) => r.id), ['r2'], 'the deleted session is gone on A too');
  assert.equal(pendingChanges(a.get(), a.get().sync.known).upserts.length, 0);
});

test('an unsynced change on this device is not overwritten by the server copy', async () => {
  const shared = { rows: [], clock: 1000 };
  const a = device({ templates: [plan('p1', 'Push')] });
  const b = device();
  await syncOnce({ db: fakeDb('u1', shared), userId: 'u1', ...a });
  await syncOnce({ db: fakeDb('u1', shared), userId: 'u1', ...b });

  b.edit({ templates: [{ ...b.get().templates[0], name: 'From B' }] });
  await syncOnce({ db: fakeDb('u1', shared), userId: 'u1', ...b });
  a.edit({ templates: [{ ...a.get().templates[0], name: 'From A (offline edit)' }] });
  await syncOnce({ db: fakeDb('u1', shared), userId: 'u1', ...a });

  assert.equal(a.get().templates[0].name, 'From A (offline edit)');
  assert.equal(shared.rows.find((r) => r.id === 'p1').data.name, 'From A (offline edit)');
});

test("accounts don't mix: another user's rows are invisible", async () => {
  const shared = { rows: [], clock: 1000 };
  await syncOnce({ db: fakeDb('u1', shared), userId: 'u1', ...device({ templates: [plan('p1', 'Mine')] }) });
  const other = device();
  await syncOnce({ db: fakeDb('u2', shared), userId: 'u2', ...other });
  assert.equal(other.get().templates.length, 0);
});

test('large histories are pulled across pages', async () => {
  const shared = { rows: [], clock: 1000 };
  const many = Array.from({ length: 2300 }, (_, i) => record(`r${i}`, i));
  await syncOnce({ db: fakeDb('u1', shared), userId: 'u1', ...device({ records: many }) });
  const fresh = device();
  await syncOnce({ db: fakeDb('u1', shared), userId: 'u1', ...fresh });
  assert.equal(fresh.get().records.length, 2300);
});
