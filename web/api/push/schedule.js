import webpush from 'web-push';
import { waitUntil, getCache } from '@vercel/functions';

// Sends a rest-over push after `delaySeconds`. The function answers at once and
// keeps waiting in the background (waitUntil). Rests longer than one function
// run hand the remainder to a fresh call.
//
// Cancelling: the app posts { cancel: restId } when a rest is skipped, replaced,
// or ends with the workout. That is recorded in Vercel's runtime cache (shared by
// this function's instances, no setup needed), and the waiting job checks it
// before sending, so a cancelled alert is never delivered.
const MAX_WAIT = 270;
const CHECK_EVERY = 5;
const REST_ID = /^[a-z0-9]{6,40}$/;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function cache() {
  try { return getCache({ namespace: 'liftlog-rest' }); } catch { return null; }
}

async function isCancelled(restId) {
  if (!restId) return false;
  try { return (await cache()?.get(restId)) === 'cancelled'; } catch { return false; }
}

/** Sleeps in short steps; resolves true early if the rest gets cancelled. */
async function waitOrCancel(seconds, restId) {
  const end = Date.now() + seconds * 1000;
  while (Date.now() < end) {
    await sleep(Math.min(CHECK_EVERY * 1000, end - Date.now()));
    if (await isCancelled(restId)) return true;
  }
  return isCancelled(restId);
}

function validSubscription(s) {
  return s && typeof s.endpoint === 'string' && /^https:\/\//.test(s.endpoint) && s.keys?.p256dh && s.keys?.auth;
}

export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).end();
  const { subscription, delaySeconds, title, body, restId, cancel } = req.body || {};
  if (cancel != null) {
    if (typeof cancel !== 'string' || !REST_ID.test(cancel)) return res.status(400).json({ error: 'bad rest id' });
    try { await cache()?.set(cancel, 'cancelled', { ttl: 2 * 3600 }); } catch { /* the service worker still drops it */ }
    return res.status(200).json({ cancelled: true });
  }
  const delay = Math.min(Math.max(Number(delaySeconds) || 0, 0), 3600);
  if (!validSubscription(subscription)) return res.status(400).json({ error: 'bad subscription' });
  if (!process.env.VAPID_PUBLIC_KEY || !process.env.VAPID_PRIVATE_KEY) return res.status(500).json({ error: 'push keys missing' });

  webpush.setVapidDetails(process.env.VAPID_SUBJECT || 'mailto:liftlog@example.com', process.env.VAPID_PUBLIC_KEY, process.env.VAPID_PRIVATE_KEY);
  const payload = JSON.stringify({ title: String(title || 'LiftLog').slice(0, 80), body: String(body || '').slice(0, 200), restId: String(restId || '') });
  const origin = `https://${req.headers.host}`;

  const job = (async () => {
    if (delay > MAX_WAIT) {
      if (await waitOrCancel(MAX_WAIT, restId)) return;
      await fetch(`${origin}/api/push/schedule`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ subscription, delaySeconds: delay - MAX_WAIT, title, body, restId }),
      });
      return;
    }
    if (await waitOrCancel(delay, restId)) return;
    try {
      await webpush.sendNotification(subscription, payload, { TTL: 120, urgency: 'high' });
    } catch (e) {
      console.error('push failed', e.statusCode, e.body);
    }
  })();
  waitUntil(job);
  res.status(202).json({ scheduled: true, delaySeconds: delay });
}
