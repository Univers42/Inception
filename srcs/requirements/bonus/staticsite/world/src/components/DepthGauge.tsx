import { useEffect, useRef, useState } from 'react'
import { CHAPTERS } from '../content'
import { subscribe } from '../scroll'

// The scrollbar's replacement (MDN asks for one when a page hides its
// scrollbar): where you are in the descent, and a link to every level.
// The links are ordinary anchors, so the keyboard and the browser's own
// history work; the fill is written straight to a CSS variable, with no
// React render per scroll frame.
export function DepthGauge() {
    const [active, setActive] = useState(0)
    const rail = useRef<HTMLOListElement>(null)

    useEffect(
        () =>
            subscribe((p) => {
                rail.current?.style.setProperty('--depth', (p.x / (CHAPTERS.length - 1)).toFixed(4))
                setActive((a) => (a === p.chapter ? a : p.chapter))
            }),
        [],
    )

    return (
        <nav className="gauge" aria-label="Depth">
            <ol ref={rail}>
                {CHAPTERS.map((c, i) => (
                    <li key={c.id} className={i === active ? 'is-here' : undefined} data-depth={c.depth}>
                        <a href={`#${c.id}`} aria-current={i === active ? 'location' : undefined}>
                            <span className="gauge-mark" aria-hidden="true" />
                            <span className="gauge-label">{c.gauge}</span>
                        </a>
                    </li>
                ))}
            </ol>
        </nav>
    )
}
