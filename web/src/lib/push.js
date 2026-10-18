// Rest alerts. A Home Screen web app on iOS 16.4+ can receive Web Push; iOS
// shows those like any other notification, so they also tap your Apple Watch
// when the iPhone is locked. Our /api/push/schedule function waits until the
// rest ends and then sends the push.

const REST_KEY = '/__liftlog/rest-id';

export const isStandalone = () =>
  window.matchMedia?.('(display-mode: standalone)').matches || window.navigator.standalone === true;

export const isIOS = () => /iPhone|iPad|iPod/.test(navigator.userAgent);

export const pushSupported = () => 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;

function b64ToUint8(base64) {
  const pad = '='.repeat((4 - (base64.length % 4)) % 4);
  const raw = atob((base64 + pad).replace(/-/g, '+').replace(/_/g, '/'));
  return Uint8Array.from(raw, (c) => c.charCodeAt(0));
}

/** Asks for notification permission and subscribes. Must run from a tap. */
export async function enableAlerts() {
  if (!pushSupported()) {
    throw new Error(isIOS() && !isStandalone()
      ? 'Add LiftLog to your Home Screen first (Share → Add to Home Screen), then open it from there.'
      : 'This browser does not support notifications.');
  }
  const permission = await Notification.requestPermission();
  if (permission !== 'granted') throw new Error('Notifications are turned off for LiftLog. Turn them on in iPhone Settings → Notifications → LiftLog.');
  const reg = await navigator.serviceWorker.ready;
  const { publicKey } = await (await fetch('/api/push/key')).json();
  let sub = await reg.pushManager.getSubscription();
  if (!sub) sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: b64ToUint8(publicKey) });
  return sub.toJSON();
}

// The rest alert currently scheduled, kept across reloads so it can still be cancelled.
const CURRENT_KEY = 'liftlog.restId';
const currentRestId = () => { try { return localStorage.getItem(CURRENT_KEY) || ''; } catch { return ''; } };

async function setRestId(id) {
  try { if (id) localStorage.setItem(CURRENT_KEY, id); else localStorage.removeItem(CURRENT_KEY); } catch { /* private mode */ }
  try {
    const cache = await caches.open('liftlog-state');
    await cache.put(REST_KEY, new Response(id));
  } catch { /* the server-side cancel still stops it */ }
}

/** Tells the server not to send this alert. */
function cancelOnServer(restId) {
  if (!restId) return;
  fetch('/api/push/schedule', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    keepalive: true,
    body: JSON.stringify({ cancel: restId }),
  }).catch(() => { /* offline: the service worker drops it on arrival */ });
}

/** Removes rest alerts already showing (lock screen, Notification Center, Watch). */
export async function clearShownRestAlerts() {
  try {
    const reg = await navigator.serviceWorker?.getRegistration();
    const shown = (await reg?.getNotifications({ tag: 'rest' })) || [];
    shown.forEach((n) => n.close());
  } catch { /* not supported here */ }
}

const newRestId = () => (Math.random().toString(36).slice(2) + Math.random().toString(36).slice(2)).slice(0, 16).padEnd(8, '0');

export async function scheduleRest(subscription, endsAt, title, body) {
  // A new rest replaces the previous one (next set, +15 s): stop the old alert.
  cancelOnServer(currentRestId());
  const restId = newRestId();
  await setRestId(restId);
  try {
    await fetch('/api/push/schedule', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      keepalive: true,
      body: JSON.stringify({ subscription, delaySeconds: Math.max(1, Math.round((endsAt - Date.now()) / 1000)), title, body, restId }),
    });
  } catch (e) {
    console.warn('Could not schedule the rest alert', e);
  }
}

/** Stops the pending alert (on the server, and in the service worker as a backup)
 * and clears any rest alert already on screen. */
export function cancelRest() {
  cancelOnServer(currentRestId());
  setRestId('');
  clearShownRestAlerts();
}

export async function sendTest(subscription) {
  const res = await fetch('/api/push/schedule', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ subscription, delaySeconds: 5, title: 'LiftLog test', body: 'Rest alerts work. Lock your iPhone to feel it on your Watch.', restId: '' }),
  });
  if (!res.ok) throw new Error(`Test failed (${res.status}).`);
}
