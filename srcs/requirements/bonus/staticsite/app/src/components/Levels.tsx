import { Fragment, useEffect, useRef, useState, type CSSProperties } from 'react'
import { AnimatePresence, motion, useMotionValueEvent, useScroll, type Variants } from 'framer-motion'
import { ArrowDown, ArrowUpRight, RotateCcw } from 'lucide-react'
import { LEVELS, LINKS } from '../content'
import { DreamCanvas } from './DreamCanvas'
import { DreamCubes } from './DreamCubes'

// The motion spec of the kit's "Orbit Engineers" section transitions, turned
// into depth: going deeper, the next level arrives from below, larger and out
// of focus, while the current one recedes upward. Exits run at ~60% of an entry.
const text: Variants = {
    enter: (dir: number) => ({ opacity: 0, y: dir > 0 ? 80 : -80, scale: dir > 0 ? 1.06 : 0.94, filter: 'blur(12px)' }),
    center: {
        opacity: 1,
        y: 0,
        scale: 1,
        filter: 'blur(0px)',
        transition: { duration: 0.75, ease: [0.22, 1, 0.36, 1], staggerChildren: 0.06 },
    },
    exit: (dir: number) => ({
        opacity: 0,
        y: dir > 0 ? -60 : 60,
        scale: dir > 0 ? 0.92 : 1.05,
        filter: 'blur(10px)',
        transition: { duration: 0.45, ease: [0.55, 0, 1, 0.45] },
    }),
}

const line: Variants = {
    enter: { opacity: 0, y: 18 },
    center: { opacity: 1, y: 0, transition: { duration: 0.6, ease: [0.22, 1, 0.36, 1] } },
}

// The first title line rises word by word out of a blur (the kit's "fade-rise",
// staggered). The gradient line stays whole: background-clip: text does not
// reach into children that each get their own compositing layer.
const words: Variants = { enter: {}, center: { transition: { staggerChildren: 0.045 } } }
const word: Variants = {
    enter: { opacity: 0, y: '0.35em', filter: 'blur(8px)' },
    center: { opacity: 1, y: 0, filter: 'blur(0px)', transition: { duration: 0.7, ease: [0.22, 1, 0.36, 1] } },
}

// The scene behind a level folds in from the horizon, like the street in the
// film: tilted back on a perspective hinge at the bottom edge, then laid flat.
const fold: Variants = {
    enter: (dir: number) => ({ opacity: 0, rotateX: dir > 0 ? 24 : -24, scale: 1.1 }),
    center: { opacity: 1, rotateX: 0, scale: 1, transition: { duration: 1.1, ease: [0.22, 1, 0.36, 1] } },
    exit: (dir: number) => ({ opacity: 0, rotateX: dir > 0 ? -14 : 14, scale: 0.95, transition: { duration: 0.6, ease: [0.55, 0, 1, 0.45] } }),
}

const tintOf = (depth: number) => ({ '--tint': `var(--level-${depth})` }) as CSSProperties

// The page scrolls through a track three screens tall while the stage stays
// pinned: the scroll position picks the level. Nothing hijacks the wheel or the
// keyboard, so the page below is reached the normal way. Every control is a
// plain link to an anchor placed where its level shows (#level-1..3): deep
// links work, and so does the page without JavaScript.
//
// Anchor offsets: progress p = (scrollY - trackTop) / (trackHeight - 100dvh),
// and the track is 300dvh, so p lives on 200dvh of scroll. Level i shows for
// p in [i/3, (i+1)/3); each anchor sits a little past the start of its range.
const ANCHOR_P = [0, 0.37, 0.71]
export function Levels({ onLevelChange }: { onLevelChange: (level: number) => void }) {
    const track = useRef<HTMLElement>(null)
    const current = useRef(0)
    const [level, setLevel] = useState(0)
    const [dir, setDir] = useState(1)
    const { scrollYProgress } = useScroll({ target: track, offset: ['start start', 'end end'] })

    const follow = (p: number) => {
        const next = Math.min(LEVELS.length - 1, Math.max(0, Math.floor(p * LEVELS.length)))
        if (next === current.current) return
        setDir(next > current.current ? 1 : -1)
        current.current = next
        setLevel(next)
        onLevelChange(next)
    }
    useMotionValueEvent(scrollYProgress, 'change', follow)
    // A deep link (#level-3) scrolls before hydration: pick up where we are.
    useEffect(() => follow(scrollYProgress.get()), []) // eslint-disable-line react-hooks/exhaustive-deps

    const active = LEVELS[level]
    const last = level === LEVELS.length - 1

    return (
        <section id="levels" ref={track} aria-labelledby="levels-title" className="levels-track relative h-[300dvh]">
            <h2 id="levels-title" className="sr-only">Three levels deep</h2>
            {LEVELS.map((l, i) => (
                <span key={l.id} id={`level-${l.depth}`} aria-hidden="true" className="absolute left-0" style={{ top: `calc(200dvh * ${ANCHOR_P[i]})` }} />
            ))}
            <ol className="sr-only">
                {LEVELS.map((l) => (
                    <li key={l.id}>
                        {l.eyebrow}, {l.service}: {l.title.join(' ')} {l.body} ({l.facts.join(', ')})
                    </li>
                ))}
            </ol>

            <div className="levels-stage sticky top-0 h-dvh overflow-hidden" style={tintOf(active.depth)}>
                <AnimatePresence initial={false} custom={dir}>
                    <motion.div
                        key={level}
                        custom={dir}
                        variants={fold}
                        initial="enter"
                        animate="center"
                        exit="exit"
                        className="absolute inset-0"
                        style={{ transformOrigin: '50% 100%', transformPerspective: 1400 }}
                    >
                        <DreamCanvas scene={level} />
                    </motion.div>
                </AnimatePresence>
                <DreamCubes progress={scrollYProgress} />
                {/* legibility: darken behind the text column, keep the scene open on the right */}
                <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(ellipse_at_center,transparent_40%,var(--bg)_100%)]" />
                <div className="pointer-events-none absolute inset-0 bg-gradient-to-r from-ink/85 via-ink/35 to-transparent md:via-ink/20" />
                <div className="pointer-events-none absolute inset-x-0 bottom-0 h-40 bg-gradient-to-b from-transparent to-ink" />

                <div className="relative z-10 mx-auto flex h-full max-w-6xl flex-col justify-center px-6 pt-20 md:px-10">
                    <div aria-hidden="true" className="grid">
                        <AnimatePresence initial={false} custom={dir}>
                            <motion.div
                                key={active.id}
                                custom={dir}
                                variants={text}
                                initial="enter"
                                animate="center"
                                exit="exit"
                                className="[grid-area:1/1] max-w-3xl"
                                style={tintOf(active.depth)}
                            >
                                <motion.p variants={line} className="eyebrow flex items-center gap-3">
                                    <span className="inline-block size-2 rounded-full" style={{ background: `var(--level-${active.depth})` }} />
                                    {active.eyebrow}
                                    <span className="text-faint">/ {active.service}</span>
                                </motion.p>
                                <motion.p
                                    variants={words}
                                    className="mt-5 font-dream text-[length:var(--step-6)] leading-[var(--leading-tight)] tracking-[-0.015em]"
                                >
                                    {active.title[0].split(' ').map((w, i) => (
                                        <Fragment key={i}>
                                            <motion.span variants={word} className="inline-block">
                                                {w}
                                            </motion.span>{' '}
                                        </Fragment>
                                    ))}
                                    <br />
                                    <motion.em variants={word} className="dream-gradient inline-block">
                                        {active.title[1]}
                                    </motion.em>
                                </motion.p>
                                <motion.p variants={line} className="mt-6 max-w-xl text-[length:var(--step-1)] leading-[var(--leading-snug)] text-muted">
                                    {active.body}
                                </motion.p>
                                <motion.ul variants={line} className="mt-7 flex flex-wrap gap-2">
                                    {active.facts.map((f) => (
                                        <li key={f} className="chip">{f}</li>
                                    ))}
                                </motion.ul>
                            </motion.div>
                        </AnimatePresence>
                    </div>

                    <div className="mt-10 flex flex-wrap gap-3">
                        {last ? (
                            <a href="#level-1" className="btn btn-primary">
                                Kick: back to the surface <RotateCcw size={16} aria-hidden="true" />
                            </a>
                        ) : (
                            <a href={`#level-${active.depth + 1}`} className="btn btn-primary">
                                Go deeper <ArrowDown size={16} aria-hidden="true" />
                            </a>
                        )}
                        <a href={LINKS.blog} className="btn btn-ghost">
                            Read the blog <ArrowUpRight size={16} aria-hidden="true" />
                        </a>
                        {last && (
                            <a href={LINKS.deeper} className="btn btn-ghost">
                                Walk the levels in 3D <ArrowUpRight size={16} aria-hidden="true" />
                            </a>
                        )}
                    </div>
                </div>

                <nav aria-label="Dream levels" className="absolute right-4 bottom-6 z-10 flex gap-2 md:right-10 md:bottom-1/2 md:translate-y-1/2 md:flex-col md:gap-1">
                    {LEVELS.map((l, i) => (
                        <a
                            key={l.id}
                            href={`#level-${l.depth}`}
                            aria-current={i === level ? 'step' : undefined}
                            aria-label={`Level ${l.depth}: ${l.service}`}
                            className="group flex min-h-[44px] min-w-[44px] items-center justify-end gap-3 px-1"
                        >
                            <span className={`hidden text-sm transition-colors duration-200 md:inline ${i === level ? 'text-text' : 'text-faint group-hover:text-muted'}`}>
                                {l.service}
                            </span>
                            <span
                                className="block h-[3px] w-10 origin-right rounded-full transition-[transform,background-color] duration-300"
                                style={{
                                    transform: `scaleX(${i === level ? 1 : 0.45})`,
                                    background: i === level ? `var(--level-${l.depth})` : 'var(--line-strong)',
                                }}
                            />
                        </a>
                    ))}
                </nav>

                {level === 0 && (
                    <p className="eyebrow absolute bottom-7 left-6 z-10 hidden md:left-10 md:block" aria-hidden="true">
                        Scroll to go deeper
                    </p>
                )}
            </div>
        </section>
    )
}
