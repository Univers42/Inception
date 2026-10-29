import { useEffect, useState } from 'react'
import { motion } from 'framer-motion'
import { ArrowUpRight, BookOpen, FlaskConical, Library } from 'lucide-react'
import { LINKS } from '../content'
import { Reveal, reveal } from './Reveal'

type Post = { id: number; href: string; date: string; title: string; excerpt: string }
type WpPost = { id: number; link: string; date: string; title: { rendered: string }; excerpt: { rendered: string } }

// WordPress returns titles and excerpts as HTML: take the text, never the markup.
function plain(html: string) {
    return new DOMParser().parseFromString(html, 'text/html').body.textContent?.trim() ?? ''
}

// The latest posts come from WordPress's REST API on the same origin. On the
// bonus port (:8090) there is no WordPress behind this container, the request
// fails, and the strip simply stays the two static cards it was rendered with.
function useLatestPosts() {
    const [posts, setPosts] = useState<Post[]>([])
    useEffect(() => {
        const ac = new AbortController()
        fetch('/wp-json/wp/v2/posts?per_page=3&_fields=id,link,date,title,excerpt', {
            signal: ac.signal,
            headers: { Accept: 'application/json' },
        })
            .then((r) => (r.ok ? r.json() : Promise.reject(new Error(String(r.status)))))
            .then((list: WpPost[]) =>
                setPosts(
                    list.map((p) => ({
                        id: p.id,
                        href: new URL(p.link, location.href).pathname,
                        date: p.date.slice(0, 10),
                        title: plain(p.title.rendered),
                        excerpt: plain(p.excerpt.rendered),
                    })),
                ),
            )
            .catch(() => setPosts([]))
        return () => ac.abort()
    }, [])
    return posts
}

const DOORS = [
    { href: LINKS.blog, icon: BookOpen, title: 'The journal', text: 'Engineering notes: the bugs, the measurements and the fixes, one post at a time.' },
    { href: LINKS.wiki, icon: Library, title: 'The wiki', text: 'Every service, every decision, three levels deep. Start here before a defense.' },
    { href: LINKS.lab, icon: FlaskConical, title: 'The lab', text: 'A live machine room of this stack, drawn from what the API measured seconds ago.' },
]

export function Journal() {
    const posts = useLatestPosts()
    return (
        <section id="journal" aria-labelledby="journal-title" className="scroll-mt-24 mx-auto max-w-6xl px-6 py-[var(--space-9)] md:px-10">
            <Reveal>
                <p className="eyebrow">Wake up somewhere else</p>
                <h2 id="journal-title" className="mt-4 max-w-3xl font-dream text-[length:var(--step-5)] leading-[var(--leading-tight)]">
                    The dream has a <em className="dream-gradient [--tint:var(--level-2)]">written record.</em>
                </h2>
            </Reveal>

            <ul className="mt-12 grid gap-3 md:grid-cols-3">
                {DOORS.map((d, i) => (
                    <motion.li key={d.href} {...reveal(i * 0.05)}>
                        <a
                            href={d.href}
                            className="group flex h-full flex-col gap-4 rounded-[var(--radius-l)] border border-line bg-surface p-6 transition-[border-color,transform] duration-300 hover:-translate-y-0.5 hover:border-line-strong"
                        >
                            <d.icon size={22} className="text-accent" aria-hidden="true" />
                            <h3 className="font-dream text-[length:var(--step-3)] leading-none">{d.title}</h3>
                            <p className="text-[0.95rem] leading-[var(--leading-body)] text-muted">{d.text}</p>
                            <span className="mt-auto inline-flex items-center gap-1.5 text-sm text-link group-hover:text-[var(--link-hover)]">
                                Open {d.href} <ArrowUpRight size={15} aria-hidden="true" />
                            </span>
                        </a>
                    </motion.li>
                ))}
            </ul>

            {posts.length > 0 && (
                <div className="mt-16">
                    <h3 className="eyebrow">Latest from the journal</h3>
                    <ol className="mt-5 divide-y divide-line border-y border-line">
                        {posts.map((p, i) => (
                            <motion.li key={p.id} initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: i * 0.05, duration: 0.5 }}>
                                <a href={p.href} className="group grid gap-2 py-6 md:grid-cols-[8rem_1fr_auto] md:items-baseline md:gap-8">
                                    <time dateTime={p.date} className="font-code text-[0.8rem] text-faint">{p.date}</time>
                                    <span>
                                        <span className="block font-dream text-[length:var(--step-2)] leading-[var(--leading-snug)] group-hover:text-link">{p.title}</span>
                                        <span className="mt-1 line-clamp-2 text-[0.95rem] text-muted">{p.excerpt}</span>
                                    </span>
                                    <ArrowUpRight size={18} className="hidden text-faint group-hover:text-link md:block" aria-hidden="true" />
                                </a>
                            </motion.li>
                        ))}
                    </ol>
                </div>
            )}
        </section>
    )
}
