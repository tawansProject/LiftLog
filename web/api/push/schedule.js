import webpush from 'web-push';
import { waitUntil } from '@vercel/functions';

// Sends a rest-over push after `delaySeconds`. The function answers at once and
// keeps waiting in the background (waitUntil). Rests longer than one function
// run hand the remainder to a fresh call.
const MAX_WAIT = 270;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function validSubscription(s) {
  return s && typeof s.endpoint === 'string' && /^https:\/\//.test(s.endpoint) && s.keys?.p256dh && s.keys?.auth;
}

export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).end();
  const { subscription, delaySeconds, title, body, restId } = req.body || {};
  const delay = Math.min(Math.max(Number(delaySeconds) || 0, 0), 3600);
  if (!validSubscription(subscription)) return res.status(400).json({ error: 'bad subscription' });
  if (!process.env.VAPID_PUBLIC_KEY || !process.env.VAPID_PRIVATE_KEY) return res.status(500).json({ error: 'push keys missing' });

  webpush.setVapidDetails(process.env.VAPID_SUBJECT || 'mailto:liftlog@example.com', process.env.VAPID_PUBLIC_KEY, process.env.VAPID_PRIVATE_KEY);
  const payload = JSON.stringify({ title: String(title || 'LiftLog').slice(0, 80), body: String(body || '').slice(0, 200), restId: String(restId || '') });
  const origin = `https://${req.headers.host}`;

  const job = (async () => {
    if (delay > MAX_WAIT) {
      await sleep(MAX_WAIT * 1000);
      await fetch(`${origin}/api/push/schedule`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ subscription, delaySeconds: delay - MAX_WAIT, title, body, restId }),
      });
      return;
    }
    await sleep(delay * 1000);
    try {
      await webpush.sendNotification(subscription, payload, { TTL: 120, urgency: 'high' });
    } catch (e) {
      console.error('push failed', e.statusCode, e.body);
    }
  })();
  waitUntil(job);
  res.status(202).json({ scheduled: true, delaySeconds: delay });
}
