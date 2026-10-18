// Proxy for the free hosted exercise library (no API key). Keeps the app off
// the library's CORS settings and caches responses at the edge for a day.
const UPSTREAM = 'https://oss.exercisedb.dev/api/v1';
const ALLOWED = ['name', 'bodyParts', 'after', 'limit', 'targetMuscles', 'equipments'];

export default async function handler(req, res) {
  const { id, ...rest } = req.query;
  let url;
  if (id) {
    if (!/^[A-Za-z0-9_-]{1,40}$/.test(id)) return res.status(400).json({ error: 'bad id' });
    url = `${UPSTREAM}/exercises/${id}`;
  } else {
    const params = new URLSearchParams();
    for (const k of ALLOWED) if (typeof rest[k] === 'string') params.set(k, rest[k].slice(0, 100));
    url = `${UPSTREAM}/exercises?${params}`;
  }
  try {
    const upstream = await fetch(url, { headers: { Accept: 'application/json' } });
    const body = await upstream.text();
    res.status(upstream.status);
    res.setHeader('Content-Type', 'application/json');
    if (upstream.ok) res.setHeader('Cache-Control', 'public, s-maxage=86400, stale-while-revalidate=604800');
    res.send(body);
  } catch {
    res.status(502).json({ error: 'The exercise library could not be reached.' });
  }
}
