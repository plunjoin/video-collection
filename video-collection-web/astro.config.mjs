import { defineConfig } from 'astro/config';
import tailwind from '@astrojs/tailwind';
import node from '@astrojs/node';
import { loadEnv } from 'vite';

const env = loadEnv(process.env.NODE_ENV || 'development', process.cwd(), '');

const siteUrl = env.SITE_URL || env.PUBLIC_SITE_URL || process.env.SITE_URL || process.env.PUBLIC_SITE_URL;

// https://astro.build/config
export default defineConfig({
  ...(siteUrl ? { site: siteUrl } : {}),
  output: 'server',
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
          target: env.API_PROXY_TARGET || env.INTERNAL_API_URL || 'http://localhost:80',
          changeOrigin: true
        }
      }
    }
  }
});
