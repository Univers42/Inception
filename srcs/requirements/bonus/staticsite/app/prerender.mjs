// Bakes the server-rendered page into dist/index.html so the landing is
// complete without JavaScript (and for the first paint), then the client
// hydrates it. Run by `npm run build` after the client and SSR builds.
import { readFile, writeFile, rm } from 'node:fs/promises'

const { render } = await import('./dist-ssr/entry-server.js')
const template = await readFile('dist/index.html', 'utf8')
if (!template.includes('<!--app-html-->')) {
    throw new Error('dist/index.html has no <!--app-html--> placeholder')
}
await writeFile('dist/index.html', template.replace('<!--app-html-->', render()))
await rm('dist-ssr', { recursive: true, force: true })
console.log('[prerender] dist/index.html written')
