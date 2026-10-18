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
