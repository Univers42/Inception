// Cuts the wiki out of the project's own documentation (wiki.json says which
// heading feeds which page) and writes one HTML file per page plus tree.json
// into srcs/requirements/wordpress/site/content/wiki/, which the WordPress
// image ships and site/wiki.php seeds as weDocs pages.
//
// Why generated and not written: DEV_DOC.md is the graded deep reference. A
// hand-copied wiki would be a second copy that drifts the first time either is
// edited; this way the docs stay the one source and `make wiki` re-cuts them.
//
//   node build.mjs           write the files
//   node build.mjs --check   exit 1 if the committed files are stale
//
// Caveat: a section is matched by its exact heading text, the first one in
// the file; a heading that is renamed or duplicated fails the build rather
// than silently cutting the wrong part.
import { readFileSync, writeFileSync, mkdirSync, readdirSync, rmSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { Marked, Renderer } from 'marked'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '../..')
const SITE = join(ROOT, 'srcs/requirements/wordpress/site')
const OUT = join(SITE, 'content/wiki')
const REPO = 'https://github.com/Univers42/Inception/blob/main/'
const check = process.argv.includes('--check')

const manifest = JSON.parse(readFileSync(join(ROOT, 'tools/wiki/wiki.json'), 'utf8'))
const lexed = new Map()

// Relative links point into the repository; on the wiki they would 404, so
// they go to the same file on GitHub. Relative images are dropped (keeping
// their alt text): the wiki makes no third-party request. A table scrolls in
// its own box (the theme's .table-scroll): bare, the lab API's routes table
// pushed a 390 px phone's page 33 px sideways. A ```mermaid fence becomes the
// element the theme hands to Mermaid (GitHub draws the same fence itself); with
// no script it stays readable as its source.
const marked = new Marked({
    gfm: true,
    renderer: {
        link({ href, title, tokens }) {
            const text = this.parser.parseInline(tokens)
            const target = /^(https?:|mailto:|#)/.test(href) ? href : REPO + href.replace(/^\.\//, '')
            const t = title ? ` title="${title}"` : ''
            return `<a href="${target}"${t}>${text}</a>`
        },
        code({ text, lang }) {
            if (lang !== 'mermaid') return false
            return `<pre class="mermaid">${text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')}</pre>\n`
        },
        table(token) {
            return `<div class="table-scroll">${Renderer.prototype.table.call(this, token)}</div>\n`
        },
        image({ href, text }) {
            return /^https?:/.test(href) ? `<img src="${href}" alt="${text}" loading="lazy">` : `<em>${text}</em>`
        },
    },
})

// The docs wrap at 80 columns. Kept, each soft wrap became a <br /> under
// WordPress's wpautop, so paragraphs broke mid-sentence (13 on
// /wiki/architecture/). Code and codespans are other token types and keep
// their lines.
function unwrapSoftBreaks(token) {
    if (token.type === 'text' && typeof token.text === 'string') token.text = token.text.replace(/\n/g, ' ')
}

function tokensOf(file) {
    if (!lexed.has(file)) {
        const tokens = marked.lexer(readFileSync(join(ROOT, file), 'utf8'))
        marked.walkTokens(tokens, unwrapSoftBreaks)
        lexed.set(file, tokens)
    }
    return lexed.get(file)
}

// The heading and everything under it until the next heading of the same or a
// higher level (or, with `intro`, until the first heading at all). Sub-headings
// are renumbered so the page's own sections start at <h2>.
function section(file, heading, intro) {
    const tokens = tokensOf(file)
    const hits = tokens.flatMap((t, i) => (t.type === 'heading' && t.text.trim() === heading ? [i] : []))
    if (hits.length !== 1) throw new Error(`${file}: heading "${heading}" found ${hits.length} times (want exactly 1)`)
    const start = hits[0]
    const depth = tokens[start].depth
    let end = start + 1
    while (end < tokens.length) {
        const t = tokens[end]
        if (t.type === 'heading' && (intro || t.depth <= depth)) break
        end++
    }
    const body = tokens.slice(start + 1, end).map((t) => (t.type === 'heading' ? { ...t, depth: Math.max(2, t.depth - depth + 1) } : t))
    body.links = tokens.links
    const html = marked.parser(body).trim()
    // An area page (intro) may open straight on its first sub-heading; the
    // caller then uses the manifest summary. Anywhere else an empty cut is a
    // wrong heading.
    if (!html && !intro) throw new Error(`${file}: heading "${heading}" has no body`)
    return html
}

function render(node) {
    const [src, heading] = node.from.split(/#(.*)/s)
    if (src.startsWith('page:')) return readFileSync(join(SITE, 'content/pages', `${src.slice(5)}.html`), 'utf8').trim()
    return section(src, heading, node.intro === true)
}

const files = new Map()
const tree = []
const seen = new Set()
function walk(nodes, parent) {
    nodes.forEach((node, order) => {
        if (seen.has(node.slug)) throw new Error(`duplicate slug "${node.slug}"`)
        seen.add(node.slug)
        // No provenance comment in the page: wpautop wraps any leading HTML
        // comment in a <p> of its own, an empty paragraph atop every page.
        const html = render(node) || (node.summary ? `<p>${node.summary}</p>` : '')
        if (!html) throw new Error(`${node.slug}: empty page and no summary`)
        files.set(`${node.slug}.html`, html + '\n')
        tree.push({ slug: node.slug, title: node.title, parent, order, summary: node.summary ?? '' })
        walk(node.children ?? [], node.slug)
    })
}
walk(manifest.docs, null)
files.set('tree.json', JSON.stringify(tree, null, 2) + '\n')

if (check) {
    const stale = [...files].filter(([name, body]) => {
        try {
            return readFileSync(join(OUT, name), 'utf8') !== body
        } catch {
            return true
        }
    })
    const extra = readdirSync(OUT).filter((f) => !files.has(f))
    if (stale.length || extra.length) {
        console.error(`[wiki] stale: ${stale.map(([n]) => n).join(' ') || '-'}; unexpected: ${extra.join(' ') || '-'}. Run: make wiki`)
        process.exit(1)
    }
    console.log(`[wiki] up to date (${tree.length} pages)`)
} else {
    rmSync(OUT, { recursive: true, force: true })
    mkdirSync(OUT, { recursive: true })
    for (const [name, body] of files) writeFileSync(join(OUT, name), body)
    console.log(`[wiki] ${tree.length} pages written to ${OUT.slice(ROOT.length + 1)}`)
}
