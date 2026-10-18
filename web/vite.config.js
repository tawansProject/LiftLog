import { defineConfig } from 'vite';
import preact from '@preact/preset-vite';

export default defineConfig({
  plugins: [preact()],
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
