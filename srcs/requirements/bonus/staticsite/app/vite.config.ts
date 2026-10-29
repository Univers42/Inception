import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

// srcs/design (tokens + fonts) is shared with the WordPress theme. In the image
// it arrives as the `design` build context, copied to DESIGN_DIR; in a checkout
// it sits four levels up.
const designDir = process.env.DESIGN_DIR ?? fileURLToPath(new URL('../../../../design', import.meta.url))

export default defineConfig({
    plugins: [react(), tailwindcss()],
    resolve: { alias: { '@design': designDir } },
    build: {
        // Every asset under /_dream/: the edge nginx proxies exactly that prefix
        // (and the bare /) to this container; everything else is WordPress.
        assetsDir: '_dream',
        target: 'es2022',
        cssCodeSplit: false,
    },
    server: {
        fs: { allow: ['.', designDir] },
        // `npm run dev` on a host that reaches the VM: the journal strip reads
        // the real WordPress through the NAT forward (born2root: inception-https).
        proxy: {
            '/wp-json': {
                target: process.env.WP_ORIGIN ?? 'https://127.0.0.1:8445',
                secure: false,
                headers: { Host: 'dlesieur.42.fr' },
            },
        },
    },
})
