import { useEffect, useRef } from 'react'
import { CHAPTERS, EXITS, NUMBERS, type Chapter } from '../content'
import { trackScroll } from '../scroll'
import { Posts } from './Posts'

function Plate({ c, first }: { c: Chapter; first: boolean }) {
    const Heading = first ? 'h1' : 'h2'
    return (
        <div className={`plate plate-${c.id}`} data-depth={c.depth}>
            <p className="eyebrow">{c.eyebrow}</p>
            <Heading className="title" id={`${c.id}-title`}>
                {c.title[0]} <em>{c.title[1]}</em>
            </Heading>
            <p className="body">{c.body}</p>
            {c.facts.length > 0 && (
                <ul className="facts">
                    {c.facts.map((f) => (
                        <li key={f}>{f}</li>
                    ))}
                </ul>
            )}
            {c.id === 'surface' && (
                <p className="cue" aria-hidden="true">
                    <span className="cue-line" /> Scroll to descend
                </p>
            )}
            {c.id === 'dream' && <Posts />}
            {c.id === 'wake' && (
                <>
                    <ul className="exits">
                        {EXITS.map((e) => (
                            <li key={e.href}>
                                <a href={e.href}>
                                    <span className="exit-label">{e.label}</span>
                                    <span className="exit-note">{e.note}</span>
                                </a>
                            </li>
                        ))}
                    </ul>
                    <dl className="numbers">
                        {NUMBERS.map((n) => (
                            <div key={n.label}>
                                <dt>{n.label}</dt>
                                <dd>{n.value}</dd>
                            </div>
                        ))}
                    </dl>
                    <p className="again">
                        <a href="#surface">Back to the surface ↑</a>
                    </p>
                </>
            )}
        </div>
    )
}

// Each chapter is a tall section: its text plate stays pinned while the
// world moves behind it, then gives way to the next level.
export function Chapters() {
    const root = useRef<HTMLDivElement>(null)
    useEffect(() => {
        if (!root.current) return
        const pins = Array.from(root.current.querySelectorAll<HTMLElement>('.pin'))
        const measure = () => pins.forEach((p) => p.style.setProperty('--pin-top', `${Math.min(0, window.innerHeight - p.offsetHeight)}px`))
        const sizes = new ResizeObserver(measure)
        pins.forEach((p) => sizes.observe(p))
        window.addEventListener('resize', measure)
        const untrack = trackScroll(Array.from(root.current.querySelectorAll<HTMLElement>('.chapter')))
        return () => {
            untrack()
            sizes.disconnect()
            window.removeEventListener('resize', measure)
        }
    }, [])
    return (
        <div ref={root}>
            {CHAPTERS.map((c, i) => (
                <section key={c.id} id={c.id} className={`chapter chapter-${c.id}`} aria-labelledby={`${c.id}-title`}>
                    <div className="pin">
                        <Plate c={c} first={i === 0} />
                    </div>
                </section>
            ))}
        </div>
    )
}
