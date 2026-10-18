// Exercise GIF by exercise id. Looks up the exercise's current GIF link, fetches it
// (with retries when the free library is busy) and lets Vercel's CDN cache the image,
// so a saved link that broke, or a burst of thumbnails, still shows the animation.
const UPSTREAM = 'https://oss.exercisedb.dev/api/v1';

async function fetchWithRetry(url, init, tries = 3) {
  let last;
  for (let i = 0; i < tries; i++) {
    if (i) await new Promise((r) => setTimeout(r, 800 * i));
    try {
      last = await fetch(url, init);
      if (last.ok || ![429, 500, 502, 503, 504].includes(last.status)) return last;
    } catch (e) { last = null; }
  }
  return last;
}

export default async function handler(req, res) {
  const { id } = req.query;
  if (typeof id !== 'string' || !/^[A-Za-z0-9_-]{1,40}$/.test(id)) return res.status(400).json({ error: 'bad id' });
  try {
    const meta = await fetchWithRetry(`${UPSTREAM}/exercises/${id}`, { headers: { Accept: 'application/json' } });
    if (!meta?.ok) return res.status(meta?.status === 404 ? 404 : 502).json({ error: 'exercise not found' });
    let gif = (await meta.json())?.data?.gifUrl || '';
    if (gif.startsWith('http://')) gif = `https://${gif.slice(7)}`;
    let host = '';
    try { host = new URL(gif).hostname; } catch { /* invalid link */ }
    if (!gif.startsWith('https://') || !/(^|\.)exercisedb\.dev$/.test(host)) return res.status(404).json({ error: 'no animation' });
    const img = await fetchWithRetry(gif, { headers: { Accept: 'image/gif,image/*' } });
    if (!img?.ok) return res.status(502).json({ error: 'animation unavailable' });
    res.setHeader('Content-Type', img.headers.get('content-type') || 'image/gif');
    res.setHeader('Cache-Control', 'public, max-age=604800, s-maxage=2592000, stale-while-revalidate=2592000');
    res.status(200).send(Buffer.from(await img.arrayBuffer()));
  } catch {
    res.status(502).json({ error: 'The exercise library could not be reached.' });
  }
}
