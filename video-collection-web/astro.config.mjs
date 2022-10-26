import { defineConfig } from 'astro/config';
import tailwind from '@astrojs/tailwind';
import node from '@astrojs/node';

// https://astro.build/config
export default defineConfig({
  output: 'static',
  adapter: node({ mode: 'standalone' }),
  integrations: [tailwind()],
  server: {
    port: 4321,
    host: true
  },
  vite: {
    server: {
      proxy: {
        '/api': {
          // target: 'https://john-admin.bllii.com',
          target: 'http://localhost:80',
          changeOrigin: true
        }
      }
    }
  }
});
