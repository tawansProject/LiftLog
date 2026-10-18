import { get, set } from 'idb-keyval';

// All calls go through our own /api/exercises proxy, so the app never depends
// on the library's CORS settings and responses are cached at the edge.
const BASE = '/api/exercises';

export const BODY_PARTS = ['chest', 'back', 'shoulders', 'upper arms', 'lower arms', 'upper legs', 'lower legs', 'waist', 'neck', 'cardio'];

async function getJSON(params) {
  const res = await fetch(`${BASE}?${new URLSearchParams(params)}`);
  if (!res.ok) {
    throw new Error(res.status === 429 ? 'The exercise library is busy. Try again in a minute.' : `The exercise library returned an error (${res.status}).`);
  }
  return res.json();
}

const LIB_KEY = 'library.v1';
let library = null;

export async function loadLibrary() {
  if (library) return library;
  library = (await get(LIB_KEY)) || null;
  return library;
}

function searchLocal(lib, name, bodyPart) {
  const q = name.trim().toLowerCase();
  const words = q.split(/\s+/).filter(Boolean);
  return lib.filter((e) => (!bodyPart || e.bodyParts.includes(bodyPart)) &&
    words.every((w) => e.name.toLowerCase().includes(w) || e.targetMuscles.some((m) => m.includes(w))));
}

/** Search by name and/or body part. Uses the downloaded library when present. */
export async function search(name, bodyPart, cursor) {
  const lib = await loadLibrary();
  if (lib && !cursor) {
    return { data: searchLocal(lib, name, bodyPart).slice(0, 200), nextCursor: null, offline: true };
  }
  const params = { limit: '25' };
  if (name.trim()) params.name = name.trim();
  if (bodyPart) params.bodyParts = bodyPart;
  if (cursor) params.after = cursor;
  const page = await getJSON(params);
  return { data: page.data || [], nextCursor: page.meta?.hasNextPage ? page.meta.nextCursor : null };
}

export async function fetchExercise(id) {
  const lib = await loadLibrary();
  const local = lib?.find((e) => e.exerciseId === id);
  if (local) return local;
  return (await getJSON({ id })).data;
}

/** Downloads the whole free catalogue (about 1,500 exercises) for offline search. */
export async function downloadLibrary(onProgress) {
  const all = [];
  let cursor = null;
  do {
    const params = { limit: '25' };
    if (cursor) params.after = cursor;
    const page = await getJSON(params);
    all.push(...(page.data || []));
    onProgress(all.length, page.meta?.total || all.length);
    cursor = page.meta?.hasNextPage ? page.meta.nextCursor : null;
    await new Promise((r) => setTimeout(r, 250)); // be gentle with the free API
  } while (cursor);
  await set(LIB_KEY, all);
  library = all;
  return all.length;
}

export async function deleteLibrary() {
  await set(LIB_KEY, null);
  library = null;
}
