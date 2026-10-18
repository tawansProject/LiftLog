// Applies supabase/schema.sql to the database before each Vercel build, so the sync
// table exists without anyone pasting SQL. The schema is idempotent. Skips quietly when
// no database is connected (local builds, or before Supabase is added in Vercel), and
// never fails the build: the app still works on-device without the table.
import { readFile } from 'node:fs/promises';
import pg from 'pg';

const url = process.env.POSTGRES_URL_NON_POOLING || process.env.POSTGRES_URL;
if (!url) {
  console.log('[migrate] No database connected (POSTGRES_URL not set). Skipping.');
  process.exit(0);
}

// Supabase requires TLS; its certificate chain isn't in Node's default store.
const connectionString = url.replace(/([?&])sslmode=[^&]*&?/, '$1').replace(/[?&]$/, '');
const client = new pg.Client({ connectionString, ssl: { rejectUnauthorized: false }, connectionTimeoutMillis: 15000 });

try {
  const sql = await readFile(new URL('../supabase/schema.sql', import.meta.url), 'utf8');
  await client.connect();
  await client.query(sql);
  console.log('[migrate] Sync schema is up to date.');
} catch (e) {
  console.warn('[migrate] Could not apply the sync schema:', e.message);
} finally {
  await client.end().catch(() => {});
}
