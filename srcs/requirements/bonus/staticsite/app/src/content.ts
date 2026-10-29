// Everything the landing states about the stack. Each fact is taken from
// DEV_DOC.md (§3 architecture, §8.3 measured results, §11 bonus services),
// srcs/docker-compose.yml or the service's own conf/, never written for effect.
// Change the infrastructure, change this file.

export type Level = {
    id: string
    depth: 1 | 2 | 3
    service: string
    eyebrow: string
    title: [string, string]
    body: string
    facts: string[]
}

export const LEVELS: Level[] = [
    {
        id: 'door',
        depth: 1,
        service: 'nginx',
        eyebrow: 'Level 1 · The door',
        title: ['A dream within', 'a container.'],
        body:
            'Every request enters through one door. nginx terminates TLS 1.2 and 1.3 on port 443, the only port the mandatory stack publishes, and serves static files straight from a read-only volume.',
        facts: ['TLS 1.2 / 1.3 only', '443, the one door', 'nginx 1.28 · Alpine 3.23'],
    },
    {
        id: 'dream',
        depth: 2,
        service: 'WordPress + php-fpm',
        eyebrow: 'Level 2 · The dream',
        title: ['Every request', 'goes deeper.'],
        body:
            'Only PHP crosses into the second level, over FastCGI on :9000. WordPress runs on php-fpm 8.4 with WP-CLI and no web server of its own, while Redis keeps the hot objects in memory.',
        facts: ['php-fpm 8.4 + WP-CLI', 'FastCGI :9000, internal', 'Redis object cache'],
    },
    {
        id: 'limbo',
        depth: 3,
        service: 'MariaDB',
        eyebrow: 'Level 3 · Limbo',
        title: ['Where the data', 'never wakes up.'],
        body:
            'At the bottom, MariaDB 11.4 listens on :3306 inside the bridge network and nowhere else. Its files live in a named volume under /home/dlesieur/data: a container can die without the dream forgetting.',
        facts: ['MariaDB 11.4', ':3306, never published', 'named volumes on the host'],
    },
]

export type Service = {
    name: string
    role: string
    reach: string
    tier: 'mandatory' | 'bonus'
    depth?: 1 | 2 | 3
}

export const SERVICES: Service[] = [
    { name: 'nginx', role: 'TLS edge and router: WordPress at /, the blog and wiki, this page at /dream/, the lab under /lab/.', reach: '443 · public', tier: 'mandatory', depth: 1 },
    { name: 'wordpress', role: 'php-fpm 8.4 and WP-CLI. The blog and the wiki you are about to read.', reach: '9000 · internal', tier: 'mandatory', depth: 2 },
    { name: 'mariadb', role: 'MariaDB 11.4, bootstrapped once, persisted in a named volume.', reach: '3306 · internal', tier: 'mandatory', depth: 3 },
    { name: 'redis', role: 'Object cache for WordPress and the counters behind the lab API.', reach: '6379 · internal', tier: 'bonus' },
    { name: 'ftp', role: 'pure-ftpd onto the WordPress volume, TLS offered, passive range 21000–21010.', reach: '21 · published', tier: 'bonus' },
    { name: 'adminer', role: 'A database browser for MariaDB, nothing more.', reach: '8080 · published', tier: 'bonus' },
    { name: 'staticsite', role: 'This page. React and framer-motion, built inside the image, served by nginx. No PHP.', reach: '8090 · published', tier: 'bonus' },
    { name: 'dbbackup', role: 'Scheduled dumps, each verified, and a restore script beside them.', reach: 'no port', tier: 'bonus' },
    { name: 'web + api', role: 'The lab: a live machine room of this stack and the Node 24 API that drives it.', reach: '/lab/ · /api/v1/', tier: 'bonus' },
]

// DEV_DOC.md §8.3, "idle 8-core machine, Docker 29".
export const NUMBERS = [
    { value: '~13 s', label: 'true cold build', note: '--no-cache --pull, empty caches' },
    { value: '~7 s', label: 'first boot to a live site', note: 'secrets, CA, database, WordPress' },
    { value: '~3.5 s', label: 'warm restart', note: 'from down to serving' },
    { value: '420 MB', label: 'every image together', note: 'from 578 MB before the rework' },
]

export const LINKS = {
    blog: '/blog/',
    wiki: '/wiki/',
    lab: '/lab/',
    // the same three levels as a world you walk down through (world/, three.js)
    deeper: '/deeper/',
    // the maintainers' door: WordPress sends a signed-out visitor to its sign-in
    admin: '/wp-admin/',
}
