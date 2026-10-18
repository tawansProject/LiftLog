import { render } from 'preact';
import { App } from './app.jsx';
import './styles.css';
import { startAccount, setRecoveryHandler } from './lib/account.js';
import { push } from './nav.js';

render(<App />, document.getElementById('app'));

// Sign-in and background sync (does nothing until Supabase is connected in Vercel).
setRecoveryHandler(() => push({ type: 'newPassword' }));
startAccount();

if ('serviceWorker' in navigator && import.meta.env.PROD) {
  navigator.serviceWorker.register('/sw.js');
}

// Keep it feeling like an app: iOS can ignore user-scalable=no, so block pinch-zoom too.
document.addEventListener('gesturestart', (e) => e.preventDefault());
