// LiftLog service worker: offline app shell + rest alerts (Web Push).
const SHELL = 'liftlog-shell-v1';
const REST_KEY = '/__liftlog/rest-id';
const GIFS = 'liftlog-gifs-v1';

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(SHELL).then((c) => c.addAll(['/', '/manifest.webmanifest', '/icon-192.png'])).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil((async () => {
    for (const key of await caches.keys()) if (key.startsWith('liftlog-shell-') && key !== SHELL) await caches.delete(key);
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url);
  if (e.request.method === 'GET' && url.origin === location.origin && url.pathname === '/api/gif') {
    // Exercise animations: cache first so they show offline and load instantly next time.
    e.respondWith(caches.open(GIFS).then(async (c) => {
      const key = `${url.pathname}?id=${url.searchParams.get('id')}`;
      const hit = await c.match(key);
      if (hit) return hit;
      const r = await fetch(e.request);
      if (r.ok) c.put(key, r.clone());
      return r;
    }));
    return;
  }
  if (e.request.method !== 'GET' || url.origin !== location.origin || url.pathname.startsWith('/api/')) return;
  if (e.request.mode === 'navigate') {
    // Network first for the page so updates arrive; cached copy when offline.
    e.respondWith(fetch(e.request).then((r) => {
      const copy = r.clone();
      caches.open(SHELL).then((c) => c.put('/', copy));
      return r;
    }).catch(() => caches.match('/')));
    return;
  }
  // Hashed build assets and icons never change: cache first.
  e.respondWith(caches.match(e.request).then((hit) => hit || fetch(e.request).then((r) => {
    if (r.ok) { const copy = r.clone(); caches.open(SHELL).then((c) => c.put(e.request, copy)); }
    return r;
  })));
});

async function currentRestId() {
  try {
    const hit = await (await caches.open('liftlog-state')).match(REST_KEY);
    return hit ? await hit.text() : '';
  } catch { return ''; }
}

self.addEventListener('push', (e) => {
  e.waitUntil((async () => {
    let data = {};
    try { data = e.data.json(); } catch { data = { title: 'LiftLog', body: e.data?.text() || '' }; }
    const stale = data.restId && data.restId !== (await currentRestId());
    await self.registration.showNotification(data.title || 'LiftLog', {
      body: data.body || '',
      tag: 'rest',
      icon: '/icon-192.png',
      badge: '/icon-192.png',
    });
    if (stale) {
      // iOS requires every push to show something; remove the outdated one right away.
      const list = await self.registration.getNotifications({ tag: 'rest' });
      list.forEach((n) => n.close());
    }
  })());
});

self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  e.waitUntil((async () => {
    const all = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    if (all.length) return all[0].focus();
    return self.clients.openWindow('/');
  })());
});
