import { NUMBERS } from '../content'
import { Reveal } from './Reveal'

export function Numbers() {
    return (
        <section aria-labelledby="numbers-title" className="border-y border-line bg-sunken">
            <div className="mx-auto max-w-6xl px-6 py-[var(--space-9)] md:px-10">
                <Reveal>
                    <p className="eyebrow">Measured, not promised</p>
                    <h2 id="numbers-title" className="mt-4 font-dream text-[length:var(--step-4)] leading-[var(--leading-tight)]">
                        Fast enough to rebuild <em className="text-muted">between two questions.</em>
                    </h2>
                </Reveal>
                <dl className="mt-12 grid gap-px overflow-hidden rounded-[var(--radius-m)] border border-line bg-line sm:grid-cols-2 lg:grid-cols-4">
                    {NUMBERS.map((n, i) => (
                        <Reveal key={n.label} delay={i * 0.05} className="flex flex-col gap-2 bg-surface p-6">
                            <dt className="order-2 text-sm text-text">{n.label}</dt>
                            <dd className="order-1 font-dream text-[length:var(--step-4)] leading-none tabular-nums text-accent">{n.value}</dd>
                            <dd className="order-3 font-code text-[0.75rem] text-faint">{n.note}</dd>
                        </Reveal>
                    ))}
                </dl>
                <p className="mt-5 font-code text-[0.75rem] text-faint">DEV_DOC.md §8.3, idle 8-core machine, Docker 29. Numbers degrade on a loaded machine.</p>
            </div>
        </section>
    )
}
