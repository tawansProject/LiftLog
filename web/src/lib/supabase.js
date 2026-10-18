import { createClient } from '@supabase/supabase-js';

/* global __SUPABASE__ */
const cfg = typeof __SUPABASE__ === 'object' ? __SUPABASE__ : { url: '', key: '' };

/** The Supabase client, or null when this build has no Supabase project connected
 * (local development, or before it's added in Vercel). The app then stays on-device only. */
export const supabase = cfg.url && cfg.key
  ? createClient(cfg.url, cfg.key, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true, storageKey: 'liftlog.auth' },
  })
  : null;

export const accountsEnabled = !!supabase;
