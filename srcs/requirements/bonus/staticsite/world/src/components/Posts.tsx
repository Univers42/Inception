import { useEffect, useState } from 'react'

type Post = { id: number; link: string; date: string; title: { rendered: string } }

// The corridor's doors are the blog's posts: the latest four, read from
// WordPress's REST API on the same origin after the page is interactive.
// Nothing is shown until they arrive, and nothing if the API is out of reach
// (on the bonus port 8090, WordPress is on another origin).
export function Posts() {
    const [posts, setPosts] = useState<Post[]>([])
    useEffect(() => {
        const ctrl = new AbortController()
        fetch('/wp-json/wp/v2/posts?per_page=4&_fields=id,link,date,title', { signal: ctrl.signal })
            .then((r) => (r.ok ? r.json() : []))
            .then((data: Post[]) => setPosts(Array.isArray(data) ? data : []))
            .catch(() => setPosts([]))
        return () => ctrl.abort()
    }, [])
    if (!posts.length) return null
    return (
        <ul className="doors" aria-label="Latest posts">
            {posts.map((p, i) => (
                <li key={p.id}>
                    <a href={p.link}>
                        <span className="door-number" aria-hidden="true">
                            {String(201 + i * 2)}
                        </span>
                        <span className="door-title">{new DOMParser().parseFromString(p.title.rendered, 'text/html').body.textContent}</span>
                        <time dateTime={p.date}>{new Date(p.date).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })}</time>
                    </a>
                </li>
            ))}
        </ul>
    )
}
