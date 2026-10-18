import { useState } from 'preact/hooks';
import { Page, TopBar, BottomBar } from '../components.jsx';
import { pop, push, toast } from '../nav.js';
import { useStore } from '../lib/store.js';
import { accountsEnabled } from '../lib/supabase.js';
import {
  useAccount, signIn, signUp, sendPasswordReset, setNewPassword, signOut, syncNow, hasUnsyncedChanges,
} from '../lib/account.js';

const MIN_PASSWORD = 8;

const friendly = (e) => {
  const m = e?.message || String(e);
  if (/invalid login credentials/i.test(m)) return 'Wrong email or password.';
  if (/email not confirmed/i.test(m)) return 'Confirm your email first: tap the link we sent you, then sign in.';
  if (/already registered|already exists/i.test(m)) return 'There is already an account with this email. Sign in instead.';
  if (/rate limit|too many/i.test(m)) return 'Too many tries. Wait a minute and try again.';
  if (/fetch|network/i.test(m)) return "Can't reach the server. Check your connection.";
  return m;
};

/** Sign in, create an account, or ask for a password reset email. */
export function AuthPage({ mode: initial = 'signin' }) {
  const [mode, setMode] = useState(initial);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [info, setInfo] = useState('');

  const validEmail = /^\S+@\S+\.\S+$/.test(email.trim());
  const canSubmit = validEmail && (mode === 'reset' || password.length >= (mode === 'signup' ? MIN_PASSWORD : 1));

  const submit = async (e) => {
    e?.preventDefault();
    if (!canSubmit || busy) return;
    setBusy(true); setError(''); setInfo('');
    try {
      if (mode === 'signin') {
        await signIn(email.trim(), password);
        toast('Signed in. Syncing your data…');
        pop();
      } else if (mode === 'signup') {
        const { needsConfirmation } = await signUp(email.trim(), password);
        if (needsConfirmation) {
          setInfo(`We sent a confirmation link to ${email.trim()}. Tap it, then come back here and sign in.`);
          setMode('signin');
        } else {
          toast('Account created. Your data is backing up…');
          pop();
        }
      } else {
        await sendPasswordReset(email.trim());
        setInfo(`If ${email.trim()} has an account, a reset link is on its way. Open it on this phone.`);
      }
    } catch (err) {
      setError(friendly(err));
    } finally {
      setBusy(false);
    }
  };

  const title = { signin: 'Sign in', signup: 'Create account', reset: 'Reset password' }[mode];
  return (
    <Page>
      <TopBar title={title} />
      <p class="muted small">
        {mode === 'reset'
          ? "Enter your account's email and we'll send a link to choose a new password."
          : 'Your workout plans, sessions and settings are backed up to your account and synced to any device you sign in on.'}
      </p>
      <form onSubmit={submit}>
        <label class="small muted">Email</label>
        <input type="email" autocomplete="email" inputMode="email" autocapitalize="none" value={email}
          onInput={(e) => setEmail(e.currentTarget.value)} placeholder="you@example.com" />
        {mode !== 'reset' && (
          <>
            <label class="small muted mt16" style={{ display: 'block' }}>Password</label>
            <input type="password" autocomplete={mode === 'signup' ? 'new-password' : 'current-password'} value={password}
              onInput={(e) => setPassword(e.currentTarget.value)} placeholder={mode === 'signup' ? `At least ${MIN_PASSWORD} characters` : ''} />
          </>
        )}
        {error && <div class="note warn mt16">{error}</div>}
        {info && <div class="note mt16">{info}</div>}
        <button type="submit" class="btn mt16" disabled={!canSubmit || busy}>{busy ? 'Please wait…' : title}</button>
      </form>
      <div class="col mt16 center" style={{ alignItems: 'center' }}>
        {mode !== 'signin' && <button class="link" onClick={() => { setMode('signin'); setError(''); }}>I have an account: sign in</button>}
        {mode !== 'signup' && <button class="link" onClick={() => { setMode('signup'); setError(''); setInfo(''); }}>New here? Create an account</button>}
        {mode === 'signin' && <button class="link" onClick={() => { setMode('reset'); setError(''); setInfo(''); }}>Forgot password?</button>}
      </div>
    </Page>
  );
}

/** Shown after opening a password-reset link. */
export function NewPasswordPage() {
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const save = async (e) => {
    e?.preventDefault();
    if (password.length < MIN_PASSWORD || busy) return;
    setBusy(true); setError('');
    try {
      await setNewPassword(password);
      toast('Password changed');
      pop();
    } catch (err) {
      setError(friendly(err));
    } finally {
      setBusy(false);
    }
  };
  return (
    <Page>
      <TopBar title="New password" />
      <form onSubmit={save}>
        <label class="small muted">New password</label>
        <input type="password" autocomplete="new-password" value={password} onInput={(e) => setPassword(e.currentTarget.value)}
          placeholder={`At least ${MIN_PASSWORD} characters`} />
        {error && <div class="note warn mt16">{error}</div>}
        <button type="submit" class="btn mt16" disabled={password.length < MIN_PASSWORD || busy}>{busy ? 'Saving…' : 'Save new password'}</button>
      </form>
      <p class="small muted mt16">If you opened this link in Safari, sign in with the new password in the LiftLog app on your Home Screen afterwards.</p>
    </Page>
  );
}

function ago(ms) {
  const s = Math.round((Date.now() - ms) / 1000);
  if (s < 60) return 'just now';
  if (s < 3600) return `${Math.round(s / 60)} min ago`;
  if (s < 86400) return `${Math.round(s / 3600)} h ago`;
  return new Date(ms).toLocaleDateString();
}

/** Account card at the top of Settings. */
export function AccountCard() {
  const s = useStore();
  const { session, status } = useAccount();
  if (!accountsEnabled) {
    return (
      <div class="card">
        <div class="bold">Account</div>
        <p class="small muted">Sign-in isn't set up for this version yet, so your data stays on this iPhone. Use Export backup below to keep a copy.</p>
      </div>
    );
  }
  if (!session) {
    return (
      <div class="card">
        <div class="bold">Back up and sync</div>
        <p class="small muted">Sign in to save your workout plans, sessions and settings to your account, so they survive a reinstall and appear on other devices.</p>
        <div class="row">
          <button class="btn small" onClick={() => push({ type: 'auth', mode: 'signin' })}>Sign in</button>
          <button class="btn secondary small" onClick={() => push({ type: 'auth', mode: 'signup' })}>Create account</button>
        </div>
      </div>
    );
  }
  const line = {
    syncing: 'Syncing…',
    offline: 'Offline. Changes sync when you’re back online.',
    error: `Couldn't sync: ${status.error}`,
    idle: s.sync?.lastSyncedAt ? `Synced ${ago(s.sync.lastSyncedAt)}` : 'Not synced yet',
  }[status.state] || '';
  const doSignOut = async () => {
    if (s.active) { alert('Finish or discard the workout in progress before signing out.'); return; }
    const warn = hasUnsyncedChanges() ? '\n\nSome changes may not be synced yet and would be lost.' : '';
    if (!confirm(`Sign out? Your data stays in your account and is removed from this iPhone.${warn}`)) return;
    try { await signOut(); toast('Signed out'); } catch (e) { alert(friendly(e)); }
  };
  return (
    <div class="card">
      <div class="row between">
        <div class="col grow">
          <div class="bold ellipsis">{session.user.email}</div>
          <div class={`small ${status.state === 'error' ? 'down' : 'muted'}`}>{line}</div>
        </div>
        <span class="sync-dot" data-state={status.state} />
      </div>
      <div class="row mt8">
        <button class="btn secondary small" disabled={status.state === 'syncing'} onClick={() => syncNow()}>Sync now</button>
        <button class="btn danger small" onClick={doSignOut}>Sign out</button>
      </div>
    </div>
  );
}
