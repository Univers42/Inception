import { useEffect, useState } from 'react'
import { LINKS } from '../content'
import { onMotion, toggleMotion } from '../motion'

function Totem() {
    return (
        <svg className="totem" width="22" height="22" viewBox="0 0 32 32" fill="none" aria-hidden="true" focusable="false">
            <path d="M16 2.5v6" stroke="#f0b45a" strokeWidth="2.2" strokeLinecap="round" />
            <path d="M4.5 11.5C9 7.8 23 7.8 27.5 11.5L16.4 29.2a.5.5 0 0 1-.8 0z" fill="#e9a63f" />
            <path d="M6.5 12.6c5.6 2.3 13.4 2.3 19 0" stroke="#1a1206" strokeOpacity=".35" strokeWidth="1.2" />
        </svg>
    )
}

export function Nav() {
    // Rendered "on" on the server; the real value arrives after hydration.
    const [reduced, setReduced] = useState(false)
    useEffect(() => onMotion(setReduced), [])

    return (
        <header className="nav">
            <a className="brand" href="#surface">
                <Totem />
                <span>
                    inception <span className="brand-sub">/ deeper</span>
                </span>
            </a>
            <nav aria-label="Site">
                <ul className="nav-links">
                    <li><a href={LINKS.landing}>Landing</a></li>
                    <li><a href={LINKS.blog}>Blog</a></li>
                    <li><a href={LINKS.wiki}>Wiki</a></li>
                    <li><a href={LINKS.lab}>Lab</a></li>
                </ul>
            </nav>
            <button type="button" className="motion" aria-pressed={reduced} onClick={toggleMotion}>
                <span className="motion-dot" aria-hidden="true" />
                {reduced ? 'Motion off' : 'Motion on'}
            </button>
            <a className="signin" href={LINKS.admin}>Sign in</a>
        </header>
    )
}
