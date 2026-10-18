// Cloud sync for signed-in users. Local-first: the app always reads and writes the
// on-device state; this module copies it to and from Supabase in the background.
//
// What syncs: workout plans (templates), sessions (records) and settings, one row each
// in `liftlog_items`. The workout in progress, the exercise cache and push settings
// stay on the device.
//
// How changes are found: `sync.known` remembers a hash of every item as last synced.
// An item whose hash differs was changed here; a known item that's gone was deleted
// here (uploaded as a tombstone so other devices delete it too).
//
// Conflicts: a change made on this device that isn't uploaded yet wins over the
// server's copy of the same item. Items have random ids, so two devices only clash
// when both edit the same plan or session between syncs.

export const SETTINGS_ID = 'main';
const PAGE = 1000;
const PUSH_BATCH = 200;
const PULL_OVERLAP_MS = 60_000; // re-read the last minute: commits can land slightly out of order

export const itemKey = (kind, id) => `${kind}:${id}`;

/** JSON with sorted keys, so the same content always hashes the same (jsonb reorders keys). */
export function stableStringify(v) {
  if (v === null || typeof v !== 'object') return JSON.stringify(v) ?? 'null';
  if (Array.isArray(v)) return `[${v.map(stableStringify).join(',')}]`;
  return `{${Object.keys(v).sort().filter((k) => v[k] !== undefined).map((k) => `${JSON.stringify(k)}:${stableStringify(v[k])}`).join(',')}}`;
}

/** FNV-1a over the stable JSON: cheap change detection, not security. */
export function hashOf(data) {
  const s = stableStringify(data);
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 0x01000193); }
  return (h >>> 0).toString(36) + s.length.toString(36);
}

/** Every syncable item in the local state, keyed by kind:id. */
export function localItems(state) {
  const items = new Map();
  for (const t of state.templates || []) items.set(itemKey('template', t.id), { kind: 'template', id: t.id, data: t });
  for (const r of state.records || []) items.set(itemKey('record', r.id), { kind: 'record', id: r.id, data: r });
  if (state.settings) items.set(itemKey('settings', SETTINGS_ID), { kind: 'settings', id: SETTINGS_ID, data: state.settings });
  return items;
}

/** What to upload: changed items, and tombstones for known items deleted here. */
export function pendingChanges(state, known) {
  const items = localItems(state);
  const upserts = [];
  for (const [key, it] of items) {
    const h = hashOf(it.data);
    if (known[key] !== h) upserts.push({ ...it, key, hash: h });
  }
  const deletions = [];
  for (const key of Object.keys(known)) {
    if (!items.has(key) && !key.startsWith('settings:')) {
      const [kind, ...rest] = key.split(':');
      deletions.push({ kind, id: rest.join(':'), key });
    }
  }
  return { upserts, deletions };
}

/** Merges rows pulled from the server into the local state. Returns the new templates,
 * records and settings plus the updated `known` map. Local unsynced changes win. */
export function applyRemote(state, known, rows) {
  const items = localItems(state);
  const nextKnown = { ...known };
  const templates = new Map((state.templates || []).map((t) => [t.id, t]));
  const records = new Map((state.records || []).map((r) => [r.id, r]));
  let settings = state.settings;
  let changed = false;

  for (const row of rows) {
    const key = itemKey(row.kind, row.id);
    const local = items.get(key);
    // Settings that were never synced from here are just this device's defaults:
    // the account's copy wins on a first sync.
    const neverSynced = known[key] === undefined;
    const changedHere = local
      ? !(neverSynced && row.kind === 'settings') && hashOf(local.data) !== known[key]
      : !neverSynced;
    if (changedHere) continue; // ours is newer; it gets uploaded next

    if (row.deleted || row.data == null) {
      if (row.kind === 'template' && templates.delete(row.id)) changed = true;
      if (row.kind === 'record' && records.delete(row.id)) changed = true;
      delete nextKnown[key];
      continue;
    }
    if (row.kind === 'template') templates.set(row.id, row.data);
    else if (row.kind === 'record') records.set(row.id, row.data);
    else if (row.kind === 'settings') settings = { ...settings, ...row.data };
    else continue;
    nextKnown[key] = hashOf(row.data);
    changed = true;
  }

  return {
    changed,
    known: nextKnown,
    templates: [...templates.values()],
    records: [...records.values()].sort((a, b) => a.startedAt - b.startedAt),
    settings,
  };
}

/** One full sync round: pull what changed on the server, merge, push what changed here.
 * `db` is a Supabase client; `get`/`set` read and write the app state. */
export async function syncOnce({ db, userId, get, set }) {
  let sync = get().sync;
  if (!sync || sync.userId !== userId) {
    // First sync for this account on this device: merge everything both ways.
    sync = { userId, known: {}, cursor: null };
  }

  // 1. Pull.
  const since = sync.cursor ? new Date(Date.parse(sync.cursor) - PULL_OVERLAP_MS).toISOString() : null;
  let rows = [];
  for (let from = 0; ; from += PAGE) {
    let q = db.from('liftlog_items').select('kind,id,data,deleted,updated_at').order('updated_at', { ascending: true }).range(from, from + PAGE - 1);
    if (since) q = q.gt('updated_at', since);
    const { data, error } = await q;
    if (error) throw error;
    rows = rows.concat(data || []);
    if (!data || data.length < PAGE) break;
  }
  let cursor = sync.cursor;
  for (const r of rows) if (!cursor || r.updated_at > cursor) cursor = r.updated_at;

  const merged = applyRemote(get(), sync.known, rows);
  sync = { ...sync, known: merged.known, cursor };
  set(merged.changed
    ? { templates: merged.templates, records: merged.records, settings: merged.settings, sync }
    : { sync });

  // 2. Push.
  const { upserts, deletions } = pendingChanges(get(), sync.known);
  const payload = [
    ...upserts.map((u) => ({ kind: u.kind, id: u.id, data: u.data, deleted: false, _key: u.key, _hash: u.hash })),
    ...deletions.map((d) => ({ kind: d.kind, id: d.id, data: null, deleted: true, _key: d.key })),
  ];
  const known = { ...sync.known };
  for (let i = 0; i < payload.length; i += PUSH_BATCH) {
    const batch = payload.slice(i, i + PUSH_BATCH);
    const { data, error } = await db.from('liftlog_items')
      .upsert(batch.map(({ _key, _hash, ...row }) => row), { onConflict: 'user_id,kind,id' })
      .select('updated_at');
    if (error) throw error;
    for (const p of batch) { if (p.deleted) delete known[p._key]; else known[p._key] = p._hash; }
    for (const r of data || []) if (!cursor || r.updated_at > cursor) cursor = r.updated_at;
  }
  sync = { ...get().sync, userId, known, cursor, lastSyncedAt: Date.now() };
  set({ sync });
  return { pulled: rows.length, pushed: payload.length };
}
