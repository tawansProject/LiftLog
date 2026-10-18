import { defineConfig } from 'vite';
import preact from '@preact/preset-vite';

export default defineConfig({
  plugins: [preact()],
  define: {
    // Vercel sets these during the build: production (main), preview (staging and other branches).
    __APP_ENV__: JSON.stringify({
      vercelEnv: process.env.VERCEL_ENV || 'development',
      branch: process.env.VERCEL_GIT_COMMIT_REF || '',
      commit: process.env.VERCEL_GIT_COMMIT_SHA || '',
    }),
    // Supabase project for sign-in and sync. Vercel's Supabase integration sets these per
    // environment (production / preview). The anon key is meant to be public: row-level
    // security in supabase/schema.sql is what protects each user's data.
    __SUPABASE__: JSON.stringify({
      url: process.env.VITE_SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL || process.env.SUPABASE_URL || '',
      key: process.env.VITE_SUPABASE_ANON_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY
        || process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_PUBLISHABLE_KEY || '',
    }),
  },
  server: {
    proxy: {
      // Local dev only: on Vercel, /api is served by the functions in api/.
      '/api/exercises': {
        target: 'https://oss.exercisedb.dev',
        changeOrigin: true,
        rewrite: (p) => {
          const url = new URL(p, 'http://x');
          const id = url.searchParams.get('id');
          return id ? `/api/v1/exercises/${id}` : `/api/v1/exercises${url.search}`;
        },
      },
    },
  },
});
