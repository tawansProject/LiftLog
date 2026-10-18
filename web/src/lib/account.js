import { useEffect, useState } from 'preact/hooks';
import { supabase, accountsEnabled } from './supabase.js';
import { getState, setState, subscribe, DEFAULT_SETTINGS } from './store.js';
import { syncOnce } from './sync.js';

// Signed-in account and background sync. Sync runs after sign-in, when the app opens or
// comes back to the screen, and a few seconds after plans, sessions or settings change.

let session = null;
let status = { state: accountsEnabled ? 'idle' : 'off', error: null }; // off | idle | syncing | error | offline
const watchers = new Set();
const emit = () => watchers.forEach((f) => f({ session, status }));

export function useAccount() {
  const [v, set] = useState({ session, status });
  useEffect(() => { watchers.add(set); set({ session, status }); return () => watchers.delete(set); }, []);
  return v;
}

const setStatus = (s) => { status = { ...status, ...s }; emit(); };

// MARK: Sync scheduling

let running = false;
let again = false;
let timer = null;
let applying = false; // our own state writes shouldn't schedule another sync

export async function syncNow() {
  if (!supabase || !session) return;
  if (running) { again = true; return; }
  running = true;
  clearTimeout(timer);
  setStatus({ state: 'syncing', error: null });
  try {
    await syncOnce({
      db: supabase,
      userId: session.user.id,
      get: getState,
      set: (patch) => { applying = true; try { setState(patch); } finally { applying = false; } },
    });
    setStatus({ state: 'idle', error: null });
  } catch (e) {
    const offline = !navigator.onLine || /fetch|network/i.test(e?.message || '');
    setStatus({ state: offline ? 'offline' : 'error', error: offline ? null : (e?.message || 'Sync failed') });
  } finally {
    running = false;
    if (again) { again = false; scheduleSync(500); }
  }
}

export function scheduleSync(delay = 3000) {
  if (!supabase || !session) return;
  clearTimeout(timer);
  timer = setTimeout(syncNow, delay);
}

// MARK: Sign-in

const origin = () => window.location.origin;

export async function signUp(email, password) {
  const { data, error } = await supabase.auth.signUp({ email, password, options: { emailRedirectTo: origin() } });
  if (error) throw error;
  return { needsConfirmation: !data.session };
}

export async function signIn(email, password) {
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw error;
}

export async function sendPasswordReset(email) {
  const { error } = await supabase.auth.resetPasswordForEmail(email, { redirectTo: origin() });
  if (error) throw error;
}

export async function setNewPassword(password) {
  const { error } = await supabase.auth.updateUser({ password });
  if (error) throw error;
}

/** True when something changed here that hasn't reached the account yet. */
export function hasUnsyncedChanges() {
  const s = getState();
  return status.state !== 'idle' || !s.sync?.lastSyncedAt;
}

/** Signs out and removes this account's data from the device (it stays in the account). */
export async function signOut() {
  clearTimeout(timer);
  await supabase.auth.signOut();
  setState({
    templates: [], records: [], settings: { ...DEFAULT_SETTINGS }, sync: null, lastFinishedId: null, draft: null,
  });
}

// MARK: Start-up

let onRecovery = () => {};
/** Called when the user opens a password-reset link, to show the "new password" page. */
export const setRecoveryHandler = (f) => { onRecovery = f; };

export function startAccount() {
  if (!supabase) return;
  supabase.auth.getSession().then(({ data }) => {
    session = data.session;
    emit();
    if (session) syncNow();
  });
  supabase.auth.onAuthStateChange((event, s) => {
    session = s;
    emit();
    if (event === 'PASSWORD_RECOVERY') onRecovery();
    if (event === 'SIGNED_IN') scheduleSync(0);
  });
  subscribe((s, prev) => {
    if (applying || !session) return;
    if (s.templates !== prev.templates || s.records !== prev.records || s.settings !== prev.settings) scheduleSync();
  });
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') scheduleSync(0); });
  window.addEventListener('online', () => scheduleSync(0));
}
