// srcs/requirements/bonus/web/app/astro.config.mjs
import { defineConfig } from 'astro/config';

export default defineConfig({
  // A static site: every page is HTML on disk. Content that comes from the
  // database is rendered from the JSON snapshots in src/data at build time;
  // only the islands talk to /api/v1/ in the browser.
  output: 'static',
  // Served under https://<domain>/lab/ by the edge nginx.
  base: '/lab',
  trailingSlash: 'always',
  build: {
    format: 'directory',
    // Never inline: the CSP forbids inline <style> and <script>, so every
    // stylesheet is a file and every script a module.
    inlineStylesheets: 'never',
    assets: '_astro',
  },
  compressHTML: true,
  devToolbar: { enabled: false },
  vite: {
    build: {
      // Keep assets as files rather than data: URIs (fonts, in particular).
      assetsInlineLimit: 0,
    },
  },
});
