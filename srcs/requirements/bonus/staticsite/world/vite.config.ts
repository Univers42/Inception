import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// srcs/design (tokens + fonts) is shared with the landing and the WordPress
// theme. In the image it arrives as the `design` build context, copied to
// DESIGN_DIR; in a checkout it sits four levels up.
const designDir = process.env.DESIGN_DIR ?? fileURLToPath(new URL('../../../../design', import.meta.url))

export default defineConfig({
    // The site lives at /deeper/: the edge nginx proxies that prefix to the
    // staticsite container, beside the landing at the bare /.
    base: '/deeper/',
    plugins: [react()],
    resolve: { alias: { '@design': designDir } },
    build: {
        assetsDir: '_world',
        target: 'es2022',
        cssCodeSplit: false,
    },
    worker: { format: 'es' },
    server: {
        fs: { allow: ['.', designDir] },
        proxy: {
            '/wp-json': {
                target: process.env.WP_ORIGIN ?? 'https://127.0.0.1:8445',
                secure: false,
                headers: { Host: 'dlesieur.42.fr' },
            },
        },
    },
})
