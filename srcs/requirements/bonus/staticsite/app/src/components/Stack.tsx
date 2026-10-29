import { motion } from 'framer-motion'
import { SERVICES } from '../content'
import { Reveal, reveal } from './Reveal'

export function Stack() {
    return (
        <section id="stack" aria-labelledby="stack-title" className="scroll-mt-24 relative mx-auto max-w-6xl px-6 py-[var(--space-9)] md:px-10">
            <Reveal>
                <p className="eyebrow">The stack</p>
                <h2 id="stack-title" className="mt-4 max-w-3xl font-dream text-[length:var(--step-5)] leading-[var(--leading-tight)]">
                    Ten containers. <em className="text-muted">One door.</em>
                </h2>
                <p className="mt-5 max-w-2xl text-[length:var(--step-1)] leading-[var(--leading-snug)] text-muted">
                    Every service is built from its own Dockerfile on Alpine 3.23: no pre-made service image, no <code className="font-code text-text">latest</code> tag, and every daemon runs as PID 1.
                </p>
            </Reveal>

            <ul className="mt-12 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                {SERVICES.map((s, i) => (
                    <motion.li
                        key={s.name}
                        {...reveal((i % 3) * 0.05)}
                        className="relative flex h-full flex-col gap-3 overflow-hidden rounded-[var(--radius-m)] border border-line bg-surface p-5"
                        style={s.depth ? { boxShadow: `inset 0 2px 0 var(--level-${s.depth})` } : undefined}
                    >
                        <div className="flex items-center justify-between gap-3">
                            <h3 className="font-code text-[0.95rem] font-medium text-text">{s.name}</h3>
                            <span className={`eyebrow !text-[0.66rem] ${s.tier === 'mandatory' ? '!text-accent' : ''}`}>{s.tier}</span>
                        </div>
                        <p className="text-[0.95rem] leading-[var(--leading-body)] text-muted">{s.role}</p>
                        <p className="mt-auto font-code text-[0.78rem] text-faint">{s.reach}</p>
                    </motion.li>
                ))}
            </ul>
        </section>
    )
}
