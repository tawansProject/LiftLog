export default function handler(req, res) {
  res.setHeader('Cache-Control', 'public, max-age=3600');
  res.json({ publicKey: process.env.VAPID_PUBLIC_KEY || '' });
}
