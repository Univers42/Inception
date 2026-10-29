// What the descent says about the stack. Every fact comes from DEV_DOC.md
// (§3 architecture, §8.3 measured results), srcs/docker-compose.yml or the
// service's own conf/, as on the landing (staticsite/app/src/content.ts).
// Change the infrastructure, change this file.

export type ChapterId = 'surface' | 'door' | 'dream' | 'limbo' | 'wake'

export type Chapter = {
    id: ChapterId
    gauge: string // the depth gauge's label
    eyebrow: string
    title: [string, string]
    body: string
    facts: string[]
    depth: 0 | 1 | 2 | 3
}

export const CHAPTERS: Chapter[] = [
    {
        id: 'surface',
        gauge: 'Surface',
        eyebrow: 'Inception · 42 · a descent',
        title: ['Go deeper.', 'Ten containers, one door.'],
        body:
            'This is the Inception stack as a place. Scroll, and you walk down through it, one dream level per service, each one further from the surface than the last.',
        facts: ['10 containers, one bridge network', '443: the only door of the mandatory stack', 'every image built from Alpine 3.23'],
        depth: 0,
    },
    {
        id: 'door',
        gauge: 'nginx',
        eyebrow: 'Level 1 · The door · nginx',
        title: ['Every request', 'enters here.'],
        body:
            'nginx terminates TLS 1.2 and 1.3 on port 443, the only port the mandatory stack publishes, and serves static files straight from a read-only volume. Everything else is passed on, one level down.',
        facts: ['TLS 1.2 / 1.3 only', '443, the one door', 'nginx 1.28 · Alpine 3.23'],
        depth: 1,
    },
    {
        id: 'dream',
        gauge: 'WordPress',
        eyebrow: 'Level 2 · The dream · WordPress',
        title: ['Only PHP', 'goes deeper.'],
        body:
            'Requests for PHP cross into the second level over FastCGI on :9000. WordPress runs on php-fpm 8.4 with WP-CLI and no web server of its own, while Redis keeps the hot objects in memory. Behind each door of this corridor, a post.',
        facts: ['php-fpm 8.4 + WP-CLI', 'FastCGI :9000, internal', 'Redis object cache'],
        depth: 2,
    },
    {
        id: 'limbo',
        gauge: 'MariaDB',
        eyebrow: 'Level 3 · Limbo · MariaDB',
        title: ['Where the data', 'never wakes up.'],
        body:
            'At the bottom, MariaDB 11.4 listens on :3306 inside the bridge network and nowhere else. Its files live in a named volume under /home/dlesieur/data: a container can die without the dream forgetting.',
        facts: ['MariaDB 11.4', ':3306, never published', 'named volumes on the host'],
        depth: 3,
    },
    {
        id: 'wake',
        gauge: 'The kick',
        eyebrow: 'The kick',
        title: ['Wake up.', 'Then read how it was built.'],
        body:
            'The top is still spinning. Everything you just crossed is written down: the blog follows the build one problem at a time, the wiki holds every detail, and the lab shows the machine room live.',
        facts: [],
        depth: 0,
    },
]

// DEV_DOC.md §8.3, "idle 8-core machine, Docker 29".
export const NUMBERS = [
    { value: '~13 s', label: 'true cold build' },
    { value: '~7 s', label: 'first boot to a live site' },
    { value: '~3.5 s', label: 'warm restart' },
    { value: '420 MB', label: 'every image together' },
]

export const EXITS = [
    { href: '/blog/', label: 'Read the blog', note: 'The build, one problem at a time' },
    { href: '/wiki/', label: 'Open the wiki', note: 'Three levels deep, written down' },
    { href: '/lab/', label: 'Visit the lab', note: 'The machine room, live' },
    { href: '/dream/', label: 'Back to the landing', note: 'The surface, in two dimensions' },
]

export const LINKS = {
    landing: '/dream/',
    blog: '/blog/',
    wiki: '/wiki/',
    lab: '/lab/',
    // the maintainers' door: WordPress sends a signed-out visitor to its sign-in
    admin: '/wp-admin/',
}
