import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// In development Vite proxies /api, /health and /ready to the Node API.
// In production the SAME paths are proxied by nginx (see the Docker module).
// Result: the frontend code never hard-codes an API host. That is what lets
// one build run unchanged in dev, staging and prod.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      '/api': 'http://localhost:3000',
      '/health': 'http://localhost:3000',
      '/ready': 'http://localhost:3000',
    },
  },
  build: {
    outDir: 'dist',
    sourcemap: false,
  },
});
